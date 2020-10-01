import UIKit
import Flutter
import WidgetKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
          UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    if(!UserDefaults.standard.bool(forKey: "Notification")) {
        UIApplication.shared.cancelAllLocalNotifications()
        UserDefaults.standard.set(true, forKey: "Notification")
    }
    //Course app widget must be iOS 14 above
    if #available(iOS 14.0, *) {
        //Course data export to app group
        let standrtUserDefaults = UserDefaults.standard
        print(UserDefaults.standard.dictionaryRepresentation().keys)
        let groupUserDefaults = UserDefaults(suiteName: "group.ap_common.course_app_widget")
        if let semester = standrtUserDefaults.string(forKey: "flutter.ap_common.current_semester_code"){
            print("sememster \(semester)")
            if let text = standrtUserDefaults.string(forKey: "flutter.ap_common.course_data_\(semester)"){
                print("text \(text)")
                groupUserDefaults?.set(text, forKey: "course_notify")
            }
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
