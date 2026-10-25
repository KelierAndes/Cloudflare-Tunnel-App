#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <dwmapi.h>

#include "flutter_window.h"
#include "utils.h"

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  const std::wstring launch_line(::GetCommandLineW());
  // Started by the "Run" registry entry (or manually) -> stay in the tray.
  const bool start_hidden = launch_line.find(L"--minimized") != std::wstring::npos ||
                            launch_line.find(L"--autostart") != std::wstring::npos;

#ifndef _DEBUG
  // One instance owns the tunnels: a repeated launch just surfaces the window
  // of the instance that is already running, instead of starting a second
  // cloudflared host that competes for the same tunnels.
  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, L"Local\\cf_tunnel_manager.instance");
  if (single_instance != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(cf_window::kClassName, cf_window::kTitle);
    if (existing != nullptr) {
      ::PostMessageW(existing, cf_window::kShowFromSecondInstance, 0, 0);
    }
    ::CloseHandle(single_instance);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }
  // Kept open for the process lifetime; closing it would free the lock.
  (void)single_instance;
#endif

  // Keep cloudflared children inside a job object so they are terminated when
  // the app exits, even if the window is closed or the process crashes.
  HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
  if (job != nullptr) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION job_info{};
    job_info.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (::SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                  &job_info, sizeof(job_info))) {
      ::AssignProcessToJobObject(job, ::GetCurrentProcess());
    }
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetStartHidden(start_hidden);
  Win32Window::Point origin(40, 30);
  Win32Window::Size size(1240, 820);
  if (!window.Create(cf_window::kTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Keep the native title bar in dark mode so it blends with the app shell.
  HWND handle = window.GetHandle();
  BOOL dark_title = TRUE;
  ::DwmSetWindowAttribute(handle, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_title,
                          sizeof(dark_title));
  COLORREF caption_color = RGB(11, 15, 21);
  ::DwmSetWindowAttribute(handle, DWMWA_CAPTION_COLOR, &caption_color,
                          sizeof(caption_color));
  COLORREF text_color = RGB(233, 238, 247);
  ::DwmSetWindowAttribute(handle, DWMWA_TEXT_COLOR, &text_color,
                          sizeof(text_color));

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
