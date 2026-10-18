#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>
#pragma comment(lib, "Shell32.lib")

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutex[] = L"Local\\FreedomMusic.SingleInstance";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"Freedom Music";

HWND FindRunningWindow() {
  HWND hwnd = nullptr;
  for (int attempt = 0; attempt < 50 && hwnd == nullptr; ++attempt) {
    hwnd = ::FindWindowW(kWindowClassName, kWindowTitle);
    if (hwnd == nullptr) {
      ::Sleep(100);
    }
  }
  return hwnd;
}

void RestoreTaskbarButton(HWND hwnd) {
  ITaskbarList* taskbar = nullptr;
  const HRESULT created = ::CoCreateInstance(
      CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_ITaskbarList,
      reinterpret_cast<void**>(&taskbar));
  if (FAILED(created) || taskbar == nullptr) {
    return;
  }
  if (SUCCEEDED(taskbar->HrInit())) {
    taskbar->AddTab(hwnd);
  }
  taskbar->Release();
}

void BringToFront(HWND hwnd) {
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  } else {
    ::ShowWindow(hwnd, SW_SHOW);
  }

  HWND foreground = ::GetForegroundWindow();
  const DWORD current_thread = ::GetCurrentThreadId();
  DWORD foreground_thread = 0;
  if (foreground != nullptr) {
    foreground_thread = ::GetWindowThreadProcessId(foreground, nullptr);
  }
  const DWORD target_thread = ::GetWindowThreadProcessId(hwnd, nullptr);

  const bool attached_foreground =
      foreground_thread != 0 && foreground_thread != current_thread &&
      ::AttachThreadInput(current_thread, foreground_thread, TRUE) == TRUE;
  const bool attached_target =
      target_thread != 0 && target_thread != current_thread &&
      target_thread != foreground_thread &&
      ::AttachThreadInput(current_thread, target_thread, TRUE) == TRUE;

  ::BringWindowToTop(hwnd);
  if (!::SetForegroundWindow(hwnd)) {
    INPUT input = {};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = VK_MENU;
    ::SendInput(1, &input, sizeof(INPUT));
    ::SetForegroundWindow(hwnd);
    input.ki.dwFlags = KEYEVENTF_KEYUP;
    ::SendInput(1, &input, sizeof(INPUT));
  }

  if (attached_foreground) {
    ::AttachThreadInput(current_thread, foreground_thread, FALSE);
  }
  if (attached_target) {
    ::AttachThreadInput(current_thread, target_thread, FALSE);
  }
}

// A second launch focuses the window that is already running, including one
// hidden to the tray, and then exits.
bool ActivateRunningInstance() {
  const HWND hwnd = FindRunningWindow();
  if (hwnd == nullptr) {
    return false;
  }

  const HRESULT com = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  RestoreTaskbarButton(hwnd);
  BringToFront(hwnd);
  if (SUCCEEDED(com)) {
    ::CoUninitialize();
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ::SetLastError(0);
  const HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningInstance();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Helps Windows Media overlay show "Freedom Music" instead of Unknown.
  SetCurrentProcessExplicitAppUserModelID(L"FreedomMusic.Player");

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Freedom Music", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
