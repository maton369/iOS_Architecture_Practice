//
//  LaunchTracker.swift
//
//  このファイルは「アプリがどの経路で起動されたか」を正規化し、
//  分析（Analytics）に送信するためのユーティリティである。
//
//  iOS アプリの起動経路は多岐にわたる。
//   - 通常起動（アイコンタップ）
//   - 通知（ローカル / リモート）
//   - Deep Link（Universal Links / URL Scheme / Dynamic Links）
//   - Spotlight（検索結果タップ / 検索継続）
//   - Widget（URL Scheme 経由など）
//   - Home Screen Quick Actions（ショートカット）
//
//  これらは AppCoordinator.LaunchType によって “入力として表現” されている。
//  LaunchTracker の役割は次の2段階である。
//
//  1) LaunchType を “分析しやすい形” に正規化（Event へマッピング）
//  2) 正規化された Event を Analytics に送信する（send）
//
//  ポイント:
//  - どの起動経路でも Event という単一の型に落とし込むことで、
//    Analytics 側の設計（ダッシュボード・集計）が楽になる。
//  - Event.create() は “ルーティング表” になっていて、
//    AppCoordinator の起動分岐と対応関係を持つ。
//  - track() は “変換して送る” の薄いラッパであり、
//    ここに複雑さを持ち込まず create() に閉じ込めている。
//

import UIKit
import CoreSpotlight
import UserNotifications

// MARK: - LaunchTracker
//
// 起動経路トラッキングのユーティリティ。
// 状態を持たず static 関数だけで完結しているため、
// 依存注入なしでも呼び出しやすい（ただしテスト性は後述の改善案参照）。
struct LaunchTracker {

    // MARK: - Event
    //
    // Analytics に送信する “起動イベント” を表す列挙型。
    //
    // ここでの設計思想:
    // - AppCoordinator.LaunchType はアプリ内部の起動情報（ルーティング用）である。
    // - Event は Analytics 用の “集計しやすいデータモデル” である。
    //
    // そのため Event は
    // - 何が起動原因だったのか（カテゴリ）
    // - 必要最低限のラベル（identifier / url / query など）
    // を持つ。
    //
    // Equatable にしているのは、テストで
    // 「この LaunchType を入れたらこの Event になる」
    // を比較しやすくする意図がある。
    enum Event: Equatable {

        /// 通常起動（アイコンタップ等）
        case normal

        /// ローカル通知からの起動
        /// identifier は通知リクエストの識別子（どの通知か）を表す。
        case localNotification(identifier: String)

        /// リモート通知（APNs）からの起動
        case remoteNotification(identifier: String)

        /// Deep Link 経由（Universal Links / URL Scheme / Dynamic Links）
        /// url を保持して、どのリンクから来たか分析できる。
        case deepLink(url: URL)

        /// Spotlight の検索結果をタップした起動
        /// resultIdentifier は Spotlight 検索結果の identifier（対象コンテンツのID等）。
        case spotlight(resultIdentifier: String)

        /// Spotlight の検索継続（インクリメンタル検索等）
        /// query は検索クエリ文字列。
        case spotlight(query: String)

        /// Widget からの起動（URL Scheme で識別子を渡す想定）
        case widget(identifier: String)

        /// Home Screen Quick Actions（ショートカット）からの起動
        /// type は shortcutItem.type（どのショートカットか）
        case homeScreen(type: String)

        // MARK: - create(launchType:)
        //
        // AppCoordinator.LaunchType を Analytics 用 Event に変換する “マッピング関数”。
        //
        // アルゴリズム:
        // 1) launchType を switch で分岐
        // 2) 起動経路に応じて Event を生成
        // 3) このアプリで追跡しない経路は nil を返す（untracked）
        //
        // ここを1箇所に閉じ込めておくことで、
        // - 起動経路の追加・修正が Event.create() のみで完結する
        // - Analytics の命名規約を統一できる
        // - AppCoordinator の start() の分岐と整合しやすい
        static func create(launchType: AppCoordinator.LaunchType) -> Event? {

            switch launchType {

            case .normal:
                // 通常起動はそのまま .normal として記録する
                return .normal

            case .notification(let request):
                // 通知起動は trigger の型でローカル/リモートを判定している。
                // iOS の通知では UNNotificationTrigger のサブクラスにより起動原因を推定できる。
                if request.trigger is UNPushNotificationTrigger {
                    // リモート通知（APNs）
                    return .remoteNotification(identifier: request.identifier)
                } else if request.trigger is UNTimeIntervalNotificationTrigger {
                    // ローカル通知（時間間隔トリガ）
                    return .localNotification(identifier: request.identifier)
                }
                // 他の trigger（カレンダー等）はこのアプリでは追跡しない想定で nil に落ちる
                //（ただし最後の return nil に到達）
                
            case .userActivity(let activity):
                // NSUserActivity 経由起動（Universal Links / Spotlight 等）。
                // activityType によって “どの入口だったか” を識別する。
                switch activity.activityType {

                case NSUserActivityTypeBrowsingWeb:
                    // Universal Links（ブラウズ）として扱う。
                    // webpageURL が取れないのは通常想定外。
                    guard let url = activity.webpageURL else {
                        // ここは “到達不能” として fatalError しているが、
                        // 実務ではクラッシュさせず nil で握りつぶす／ログに落とす方が安全。
                        fatalError("unreachable")
                    }
                    return .deepLink(url: url)

                case CSSearchableItemActionType:
                    // Spotlight 検索結果タップ。
                    // userInfo から検索結果の identifier を取得する。
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
                        fatalError("unreachable")
                    }
                    return .spotlight(resultIdentifier: identifier)

                case CSQueryContinuationActionType:
                    // Spotlight の検索継続（インクリメンタル検索）。
                    // userInfo にクエリ文字列が格納される。
                    guard let query = activity.userInfo?[CSSearchQueryString] as? String else {
                        fatalError("unreachable")
                    }
                    return .spotlight(query: query)

                default:
                    // このアプリでは追跡しない userActivity は nil として返す。
                    //（例: Handoff 等を追跡対象外にする）
                    return nil
                }

            case .openURL(let url):
                // URL Scheme / Dynamic Link 等。
                // scheme に応じて “どの入口だったか” を判定し Event を作る。
                if url.scheme == "coordinator-example-widget" {
                    // Widget からの起動想定：最後の path component を識別子として使う。
                    let identifier = url.lastPathComponent
                    return .widget(identifier: identifier)

                } else if url.scheme == "adjustSchemeExample" {
                    // Adjust のような計測 SDK 経由 URL Scheme の例。
                    // TODO: replace your adjust url scheme
                    // ここでは deepLink として扱って記録している。
                    return .deepLink(url: url)

                } else if url.scheme == "FirebaseDynamicLinksExmaple" {
                    // Firebase Dynamic Links の例。
                    // TODO: handle your FDL
                    // ここでも deepLink として記録している。
                    return .deepLink(url: url)

                } else {
                    // それ以外はこのアプリでは追跡しない URL として nil。
                    return nil
                }

            case .shortcutItem(let item):
                // Home Screen Quick Actions。
                // item.type を記録して “どのショートカットが使われたか” を分析可能にする。
                return .homeScreen(type: item.type)
            }

            // switch 内で return しきれなかった場合は nil。
            // 現状、notification の未知 trigger などがここに落ちる可能性がある。
            return nil
        }
    }

    // MARK: - track(launchType:)
    //
    // 外部から呼ぶエントリーポイント。
    // LaunchType を Event に変換できた場合のみ send(event:) で送信する。
    //
    // アルゴリズム:
    // 1) Event.create(...) を呼んで変換
    // 2) 変換できない（nil）なら何もしない（追跡対象外）
    // 3) 変換できたら send(event:) を呼ぶ
    //
    // ここを薄くしていることで、追跡ロジックは create() に集約される。
    static func track(launchType: AppCoordinator.LaunchType) {
        guard let event = Event.create(launchType: launchType) else {
            return
        }
        send(event: event)
    }

    // MARK: - send(event:)
    //
    // Analytics 送信処理。
    // 現状は TODO だが、実務では
    // - Firebase Analytics
    // - Amplitude
    // - Mixpanel
    // - 自社サーバ
    // などに送る実装が入る。
    //
    // 設計上のポイント:
    // - Event を受け取って “文字列化” や “パラメータ化” をここで行うと、
    //   Analytics 依存が LaunchTracker の内部に閉じ込められる。
    // - テスト性を上げたい場合は send を protocol 経由にして DI する設計もあり得る。
    private static func send(event: Event) {
        // TODO: send event to your analytics
        //
        // 例（概念）:
        // analytics.track(
        //   name: "app_launch",
        //   parameters: event.toParameters()
        // )
    }
}

//
// MARK: - 実務でよく検討する改善点（参考）
//
// 1) fatalError を避ける
//    - “unreachable” は理屈上到達しなくても、OS/SDK変更や未知ケースで到達する可能性がある。
//    - nil を返す or ログに落としてフォールバックする方が本番で安全。
//
// 2) 通知 trigger の網羅性
//    - UNCalendarNotificationTrigger 等も localNotification として扱うなら分岐を追加する。
//
// 3) send の DI（テスト性）
//    - static のままだとテストで送信呼び出し検証がしにくい。
//    - AnalyticsClientProtocol を注入する形にするとユニットテストが簡単になる。
//
// 4) URL の正規化
//    - url 全体を送ると個人情報や不要なパラメータが含まれる可能性がある。
//    - path / host / query の一部のみ送るなど、プライバシーと集計性を両立させる設計がよい。
//```