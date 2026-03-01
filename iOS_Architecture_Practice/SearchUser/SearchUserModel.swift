//
//  SearchUserModel.swift (想定)
//  MVPSample
//
//  このファイルは MVP における Model（正確には「データ取得/データアクセス層」）の実装である。
//  Presenter からの要求に応じて GitHub API を叩き、検索結果（[User]）を返す責務を持つ。
//
//  MVPの観点で重要なのは、Presenter が「どのAPIライブラリを使っているか」を知らなくてよい点である。
//  そのため Presenter は SearchUserModelInput というプロトコルにのみ依存し、具体の通信実装は Model 側に隠蔽される。
//  これにより、テストでは Model をモックに差し替えられる（ネットワーク無しでPresenterを検証可能）。
//
//  本実装におけるアルゴリズムは次の通り。
//    1) Presenter から query を受け取る
//    2) GitHub.Session を生成する
//    3) SearchUsersRequest を構築する
//    4) session.send(request) で非同期通信を開始する
//    5) result を Result<[User]> に変換して completion へ返す
//
//  注意点として、completion がどのスレッドで呼ばれるかは保証されないことが多い。
//  そのため UI 更新は Presenter 側で main thread に戻す（実装済み）という役割分担になっている。
//

import Foundation
import GitHub

// MARK: - Model Input (Presenter -> Model)
//
// Presenter が Model に対して依頼するためのインターフェース。
// “ユーザ検索” というユースケースを、APIライブラリ実装から切り離す役割を持つ。
protocol SearchUserModelInput {

    /// GitHub のユーザ検索を実行する。
    ///
    /// - Parameters:
    ///   - query: 検索文字列（例: "maton"）
///
/// - completion:
///   - 成功時: .success([User])（検索結果のユーザ配列）
///   - 失敗時: .failure(Error)（通信/デコード/HTTP等のエラー）
///
/// ここでの Result<[User]> は、GitHub ライブラリが提供する Result 型を利用している想定。
/// Swift標準の Result<[User], Error> に寄せる設計も多いが、ライブラリに合わせている。
    func fetchUser(
        query: String,
        completion: @escaping (Result<[User]>) -> ()
    )
}

// MARK: - Model Implementation
//
// SearchUserModel は SearchUserModelInput を満たす具体実装。
// GitHub ライブラリを使って SearchUsersRequest を送り、レスポンスから items を抜き出して返す。
final class SearchUserModel: SearchUserModelInput {

    /// ユーザ検索の実行。
    ///
    /// アルゴリズム:
    /// 1) Session を作る
    /// 2) Request を構築する（query / sort / order / page / perPage）
    /// 3) session.send で非同期送信
    /// 4) 成功なら response から items を抽出して completion(.success(items))
    /// 5) 失敗なら completion(.failure(error))
    ///
    /// 設計上のポイント:
    /// - Presenter 側は GitHub.Session / SearchUsersRequest の存在を知らない
    /// - 依存が Model 側に閉じるため、Presenter のテスト容易性が上がる
    ///
    /// 改善余地（実務寄り）:
    /// - Session を毎回生成せず DI する（テスト容易性・設定共有・コネクション再利用）
    /// - page/perPage/sort/order を引数で受け取れるようにして検索機能を拡張
    /// - completion を main thread に戻す責務をどちらに置くか明確化（現状は Presenter 側）
    func fetchUser(
        query: String,
        completion: @escaping (Result<[User]>) -> ()
    ) {

        // GitHub API 通信用セッション。
        // 毎回生成しているため、設定（認証トークンやキャッシュ等）を共有したい場合はDIが望ましい。
        let session = GitHub.Session()

        // GitHub ユーザ検索のリクエストを構築する。
        // sort/order/page/perPage を nil にしているため、APIのデフォルト挙動に従う。
        // 機能拡張するなら、これらを引数として Presenter（または別のUseCase）から渡す設計もあり得る。
        let request = SearchUsersRequest(
            query: query,
            sort: nil,
            order: nil,
            page: nil,
            perPage: nil
        )

        // 非同期でリクエストを送信する。
        // send の completion がどのスレッドで呼ばれるかはライブラリ依存であり、
        // ここではスレッド制御をしない（UI更新は Presenter 側で main に戻す想定）。
        session.send(request) { result in
            switch result {

            case .success(let response):
                // SearchUsersRequest の成功レスポンスはタプルになっている（response.0）。
                // response.0.items から検索結果のユーザ一覧を取り出して返す。
                //
                // 注意:
                // - この “.0” は型が分かりにくいので、可能なら構造体/名前付きの形に寄せたい。
                // - ただしライブラリ仕様ならここで吸収して Presenter へは [User] だけ返すのは合理的。
                completion(.success(response.0.items))

            case .failure(let error):
                // 通信失敗/デコード失敗/HTTPエラー等を、そのまま上位へ伝播させる。
                // エラーのユーザ向け表示（アラート等）は Presenter が View に命令する側で行うのがMVP的に自然。
                completion(.failure(error))
            }
        }
    }
}