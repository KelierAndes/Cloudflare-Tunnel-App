#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>
#include <windows.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Launched from the boot auto-start entry: run from the tray, no window.
  void SetStartHidden(bool start_hidden) { start_hidden_ = start_hidden; }

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void InstallTrayIcon();
  void RemoveTrayIcon();
  void HandleTrayClick(WPARAM wparam, LPARAM lparam);
  void ShowTrayMenu();
  void ShowFromTray();
  void HideToTray();
  void RequestQuit();
  void SetTrayTooltip(const std::string& utf8_text);
  bool WriteAutoStart(bool enabled);
  bool IsAutoStartRegistered();

  // The project to run.
  flutter::DartProject project_;

  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Channel used for the title bar theme, the tray and the boot entry.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  NOTIFYICONDATAW tray_data_ = {};
  bool tray_installed_ = false;
  bool hidden_in_tray_ = false;
  bool close_to_tray_ = true;
  bool force_quit_ = false;
  bool start_hidden_ = false;
  bool balloon_shown_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
