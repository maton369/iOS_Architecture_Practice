//
//  AppCoordinator.swift
//
//  このファイルは Coordinator パターンにおける “アプリ全体の起点（Root Coordinator）” を実装している。
//  AppCoordinator は主に次の責務を持つ。
//
//  1) window.rootViewController の決定（アプリのRoot UIを確立する）
//  2) TabBar / NavigationController などの “アプリ骨格” を組み立てる
//  3) 起動経路（通常起動 / 通知 / Universal Links / Spotlight / URL Scheme / Shortcut）を解析し、
//     必要なら該当フロー（子Coordinator）へルーティングする
//
//  Coordinator パターンの狙いは、ViewController から
//  - 画面遷移（push/present）
//  - 画面フローの分岐（ディープリンク等）
//  - DI（依存注入・画面生成）
//  を追い出し、遷移の意思決定を Coordinator に集約することにある。
//
//  本実装は “起動種別” を LaunchType として抽象化し、start() の中で switch により分岐している。
//  これは「アプリ起動を1本のルーティング関数」に寄せる設計であり、見通しが良い。
//

import UIKit
import UserNotifications
import CoreSpotlight

// MARK: - AppCoordinator
//
// アプリの最上位 Coordinator。
// - UIWindow を持ち、rootViewController を設定する（SceneDelegate/AppDelegate 相当の責務の一部を吸収）
// - 子Coordinator（例: RepoListCoordinator）を保持し、各フローを開始する
//
// 注意:
// - Coordinator は “画面フローの所有者” なので、子Coordinator を strong に保持するのが基本。
//   保持しないと、start() 後すぐ解放されてフローが維持できない。
class AppCoordinator: Coordinator {

    // MARK: - Root UI

    /// アプリの表示先となるウィンドウ（SceneDelegate から受け取る想定）。
    /// iOS13+ では SceneDelegate が window を持つことが多いが、
    /// Coordinator に委譲すると “起動の意思決定” をここへ集約できる。
    let window: UIWindow

    /// ルートのタブバー。
    /// AppCoordinator が “アプリの骨格” として TabBar を組み立て、その中に Navigation を配置する。
    let rootViewController: UITabBarController

    // MARK: - Launch routing input

    /// 起動経路。nil の場合は通常起動として扱う。
    /// SceneDelegate/AppDelegate 側で「今回の起動は通知経由」などを判断し、ここへ渡す設計。
    let launchType: LaunchType?

    // MARK: - Child coordinators

    /// Repo一覧フローを担当する子Coordinator。
    /// TabBar の1タブ（NavigationController）に紐づいたフローを管理する。
    var repoListCoordinator: RepoListCoordinator

    // MARK: - LaunchType
    //
    // アプリの起動原因を列挙する。
    // “起動経路ごとに必要なルーティングが異なる” のが iOS アプリの典型的な複雑さであり、
    // それを enum で閉じ込めて switch で分岐するのは読みやすい。
    enum LaunchType {

        /// 通常起動（アイコンタップなど）を表す。
        case normal

        /// 通知タップで起動した場合（ローカル/リモート含む）。
        /// UNNotificationRequest を持たせることで payload / trigger 種別を分岐できる。
        case notification(UNNotificationRequest)

        /// NSUserActivity 経由（Universal Links / Spotlight / Handoff 等）。
        case userActivity(NSUserActivity)

        /// URL Scheme / Dynamic Link 等で openURL された場合。
        case openURL(URL)

        /// ホーム画面の Quick Actions（3D Touch / Long Press Shortcut）から起動した場合。
        case shortcutItem(UIApplicationShortcutItem)
    }

    // MARK: - Init
    //
    // AppCoordinator は起動時に “アプリ骨格（Tab + Navigation）” を構築する。
    //
    // アルゴリズム:
    // 1) window と launchType を保持
    // 2) rootViewController（TabBar）を生成
    // 3) Repoタブ用の UINavigationController を生成
    // 4) その NavigationController を navigator として RepoListCoordinator を生成
    // 5) TabBar の viewControllers に配置する
    //
    // ここまでで “画面フローの容器” が完成し、start() で表示を開始する。
    init(window: UIWindow, launchType: LaunchType? = nil) {
        self.window = window
        rootViewController = .init()
        self.launchType = launchType

        // Repo一覧タブを担当する NavigationController。
        // Coordinator パターンでは、Coordinator が navigationController を所有/注入して
        // push/present の責務を Coordinator 側に寄せることが多い。
        let repoNavigationController = UINavigationController()

        // 子Coordinatorの生成（Repo一覧フロー）。
        // navigator: 画面遷移の実体（push/pop）を実行するための UINavigationController。
        self.repoListCoordinator = RepoListCoordinator(navigator: repoNavigationController)

        // TabBar にタブとして NavigationController を登録する。
        // 本サンプルは1タブのみだが、複数タブならここに追加していく。
        rootViewController.viewControllers = [repoNavigationController]
    }

    // MARK: - Start
    //
    // Coordinator.start() は「フロー開始」のメソッド。
    // AppCoordinator にとって start() は「アプリの表示開始」と「起動経路のルーティング」。
    //
    // アルゴリズム:
    // 1) window.rootViewController を rootViewController（TabBar）に設定
    // 2) window.makeKeyAndVisible() を必ず実行（deferで保証）
    // 3) launchType が nil なら通常起動として repoListCoordinator.start()
    // 4) launchType があるなら switch で起動経路を判定し、必要なフローへルーティングする
    func start() {

        // (1) Root UI を window に接続
        window.rootViewController = rootViewController

        // (2) 必ずウィンドウ表示を開始する
        // defer を使うことで、どの分岐で return しても makeKeyAndVisible が呼ばれる保証ができる。
        // これは “起動ルーティングの途中で return して表示されない” 事故を防ぐ。
        defer {
            window.makeKeyAndVisible()
        }

        // (3) launchType が指定されていなければ通常起動扱い
        // ここでは “Repo一覧フローを開始” をデフォルト動作としている。
        guard let launchType = launchType else {
            repoListCoordinator.start()
            return
        }

        // (4) 起動経路別ルーティング
        switch launchType {

        case .normal:
            // 通常起動が明示されているケース。
            // nil と同様に repoListCoordinator.start() してもよいが、
            // ここでは何もしない（＝repoListCoordinator.start() が呼ばれない）ので注意。
            // 実運用なら “normal でも開始する” のが自然なことが多い。
            break

        case .notification(let request):

            // 通知タップ起動。
            // 通知の種類（リモート/ローカル）で分岐できる。
            // ここで payload（request.content.userInfo 等）を解析し、
            // 対象画面へ遷移するのが Coordinator の典型責務。
            if request.trigger is UNPushNotificationTrigger {
                // remote notification（APNs）
                // 例:
                // - repoId を userInfo から取り出す
                // - repoListCoordinator へ “詳細画面を開け” と指示
            } else if request.trigger is UNTimeIntervalNotificationTrigger {
                // local notification（タイマー/ローカルスケジュール）
                // 例:
                // - 特定の画面を開く
            }

        case .userActivity(let userActivity):

            // NSUserActivity 起動（Universal Links / Spotlight 等）。
            // activityType を見てルーティング先を決定する。
            switch userActivity.activityType {

            case NSUserActivityTypeBrowsingWeb:
                // Universal Links / Safari経由のWeb閲覧
                // 例: userActivity.webpageURL を解析して画面遷移する
                break

            case CSSearchableItemActionType:
                // Core Spotlight の検索結果タップ
                // 例: userActivity.userInfo から identifier を取り出して詳細を開く
                break

            case CSQueryContinuationActionType:
                // Core Spotlight のインクリメンタル検索継続
                // 例: 継続クエリで一覧を開いて検索状態を復元する
                break

            default:
                // 想定外の activityType が来た場合は fatalError で落とす設計。
                // 実務では落とさずにログを残して normal フローにフォールバックする方が安全なことが多い。
                fatalError("Unreachable userActivity:'\(userActivity.activityType)")
            }

        case .openURL(let url):

            // URL Scheme / Dynamic Links 等で起動した場合。
            // scheme を判定し、各種ルーティングに振り分ける。
            if url.scheme == "coordinator-example-widget" {

                // ウィジェット等からの起動を想定。
                // lastPathComponent を identifier として扱い、該当画面へ遷移するケースが多い。
                let identifier = url.lastPathComponent
                _ = identifier
                break

            } else if url.scheme == "adjustSchemeExample" {
                // Adjust などの計測SDK用スキームの例。
                // TODO: replace your adjust url scheme
                break

            } else if url.scheme == "FirebaseDynamicLinksExmaple" {
                // Firebase Dynamic Links の例。
                // TODO: handle your FDL
                break
            }

        case .shortcutItem(let shortcutItem):

            // Quick Actions 起動。
            // shortcutItem.type を見て “どの画面を開くか” を分岐するのが定番。
            _ = shortcutItem
            break
        }
    }
}

//
// MARK: - Coordinator設計としての補足（読みやすさ・堅牢性）
//
// 1) .normal と nil の扱いがズレている可能性
//    - nil のときは repoListCoordinator.start() が呼ばれる
//    - .normal のときは break で何も起きない
//    実際は .normal でも同様に start する方が自然なことが多い。
//
// 2) 起動経路ごとの “最終到達画面” を明文化すると強い
//    - notification: 詳細へ
//    - universal link: 対象ページへ
//    - shortcut: 特定タブへ
//    など、AppCoordinator が “ルーティング表” になる。
//
// 3) 子Coordinator管理
//    複数タブ/複数フローが増えると childCoordinators 配列で管理するのが定番。
//    フロー終了時に remove することでメモリリークを防ぐ。
//
// 4) フォールバック戦略
//    fatalError は開発時には便利だが、実運用では
//    - ログだけ出して通常フローへフォールバック
//    の方が落ちにくい。
//```