#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

HWND g_view = nullptr;
WNDPROC g_view_proc = nullptr;
bool g_recover_char = false;
UINT g_last_vk = 0;
UINT g_last_scan = 0;

bool PhysicallyDown(int vk) {
  return (GetAsyncKeyState(vk) & 0x8000) != 0;
}

// Layout switch (Alt+Shift, Ctrl+Shift, Win+Space) latches a modifier inside
// Win32 and Flutter. The next letter is then a control or system character
// and never reaches the field. Release that latch before the letter arrives.
void ReleaseLatchedModifiers(HWND hwnd) {
  BYTE state[256];
  if (GetKeyboardState(state)) {
    const int mods[] = {
        VK_SHIFT,    VK_LSHIFT,   VK_RSHIFT, VK_CONTROL, VK_LCONTROL,
        VK_RCONTROL, VK_MENU,     VK_LMENU,  VK_RMENU,   VK_LWIN,
        VK_RWIN,
    };
    for (int vk : mods) {
      // The latch left by a layout switch reports the key as down even after
      // it was released. Always clear it here.
      state[vk] &= 0x7f;
    }
    SetKeyboardState(state);
  }

  struct Mod {
    UINT vk;
    bool extended;
    bool sys;
  };
  const Mod mods[] = {
      {VK_LSHIFT, false, false}, {VK_RSHIFT, false, false},
      {VK_LCONTROL, false, false}, {VK_RCONTROL, true, false},
      {VK_LMENU, false, true}, {VK_RMENU, true, true},
      {VK_LWIN, true, false}, {VK_RWIN, true, false},
  };
  for (const Mod& mod : mods) {
    const UINT scan = MapVirtualKey(mod.vk, MAPVK_VK_TO_VSC);
    LPARAM lp = 1 | (static_cast<LPARAM>(scan) << 16) | (1 << 30) |
                (static_cast<LPARAM>(1) << 31);
    if (mod.extended) lp |= (1 << 24);
    // Synchronous, so Flutter drops the modifier before the next letter.
    // An up without a matching down is ignored and not redispatched.
    SendMessage(hwnd, mod.sys ? WM_SYSKEYUP : WM_KEYUP, mod.vk, lp);
  }
  g_recover_char = true;
}

// Character the key produces in the active layout, with the latched
// modifiers ignored. Bit 2 keeps ToUnicodeEx from eating a dead key.
wchar_t CharacterForKey(UINT vk, UINT scan) {
  if (vk == 0) return 0;
  BYTE state[256] = {};
  if (PhysicallyDown(VK_SHIFT) || PhysicallyDown(VK_LSHIFT) ||
      PhysicallyDown(VK_RSHIFT)) {
    state[VK_SHIFT] = 0x80;
  }
  wchar_t buf[8] = {};
  const HKL layout = GetKeyboardLayout(0);
  const int written =
      ToUnicodeEx(vk, scan, state, buf, 4, 1 << 2, layout);
  if (written > 0 && buf[0] >= 0x20 && buf[0] != 0x7f) return buf[0];
  return 0;
}

LRESULT CALLBACK ViewProc(HWND hwnd, UINT message, WPARAM wparam,
                          LPARAM lparam) {
  switch (message) {
    case WM_INPUTLANGCHANGE:
      ReleaseLatchedModifiers(hwnd);
      break;
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
      if (wparam == VK_PROCESSKEY) {
        const UINT scan = (static_cast<UINT>(lparam) >> 16) & 0xff;
        const UINT vk =
            MapVirtualKeyEx(scan, MAPVK_VSC_TO_VK_EX, GetKeyboardLayout(0));
        if (vk != 0 && vk != VK_PROCESSKEY) wparam = vk;
      }
      g_last_vk = static_cast<UINT>(wparam);
      g_last_scan = (static_cast<UINT>(lparam) >> 16) & 0xff;
      break;
    case WM_CHAR:
    case WM_SYSCHAR:
    case WM_IME_CHAR:
      if (g_recover_char) {
        g_recover_char = false;
        // One character only. A real Ctrl/Alt chord is not what follows a
        // layout switch, and the latch makes GetAsyncKeyState agree with it.
        if (wparam < 0x20 && wparam != 0x08 && wparam != 0x09 &&
            wparam != 0x0d && wparam != 0x1b) {
          const wchar_t ch = CharacterForKey(g_last_vk, g_last_scan);
          if (ch != 0) {
            message = WM_CHAR;
            wparam = ch;
          }
        } else if (message == WM_SYSCHAR && wparam >= 0x20) {
          message = WM_CHAR;
          lparam &= ~(static_cast<LPARAM>(1) << 29);
        }
      }
      break;
    default:
      break;
  }
  return CallWindowProc(g_view_proc, hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  HWND view = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(view);
  g_view = view;
  g_view_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      view, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ViewProc)));

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (g_view && g_view_proc) {
    SetWindowLongPtr(g_view, GWLP_WNDPROC,
                     reinterpret_cast<LONG_PTR>(g_view_proc));
    g_view = nullptr;
    g_view_proc = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
