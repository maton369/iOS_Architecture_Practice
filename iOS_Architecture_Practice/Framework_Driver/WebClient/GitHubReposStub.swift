//
//  GitHubReposStub.swift
//  CleanGitHub
//
//  このファイルは Clean Architecture の “外部境界（Gateway / WebClient）” に対するスタブ実装である。
//  スタブはテストや画面確認のために、ネットワーク等の外部依存を使わずに
//  期待する形式のデータを返す「偽物の実装」を指す。
//
//  Clean Architecture では Use Case は外部データ取得に直接依存せず、
//  Protocol（ポート）を通して Gateway / WebClient を呼び出す。
//  そのため、WebClientProtocol に準拠したスタブを差し替えるだけで、
//  - API未実装でも画面を動かせる
//  - 通信不安定に影響されない
//  - ユースケースの挙動を決め打ちで再現できる
//  といった利点が得られる。
//
//  ここでのスタブは「キーワード検索で Repo 一覧を返す」という最低限の振る舞いを模倣する。
//  本物のネットワーク実装が行うのは通常：
//  - keywords をクエリに変換して HTTP リクエストを作る
//  - レスポンス JSON を decode する
//  - Result.success / failure を completion で返す
//  だが、スタブはそれらを省略し、固定のダミーデータを即座に返す。
//

import Foundation

// MARK: - GitHubReposStub
//
// WebClientProtocol に準拠したスタブ実装。
// Use Case（ReposLikesUseCase など）は WebClientProtocol の “抽象” に依存しているため、
// このスタブを注入することで、外部通信なしに Use Case を動かせる。
class GitHubReposStub: WebClientProtocol {

    // MARK: - fetch(using:completion:)
    //
    // キーワード検索を模倣するメソッド。
    // 本来は keywords を GitHub Search API の query に組み立てるが、
    // スタブなので keywords は使わずに固定の Repo を返す。
    //
    // 引数:
    // - keywords: 検索キーワード（本物実装ならクエリ生成に使う）
    // - completion: 非同期結果のコールバック（Result<[GitHubRepo]>）
    //
    // 戻り:
    // - completion(.success(repos)) を呼ぶことで Repo 配列を返す
    //
    // 注意:
    // - このスタブは “成功” しか返さない
    //   → エラー処理のテストをしたいなら、条件分岐で failure を返すスタブも用意するとよい
    func fetch(using keywords: [String], completion: @escaping (Result<[GitHubRepo]>) -> Void) {

        // ダミーデータを作成して返す。
        //
        // (0..<5) により 0,1,2,3,4 の5件の Repo を生成する。
        // ここで生成するデータは、UI が表示に必要なフィールドが埋まっていることが重要。
        // （Entity の fullName/description/language/stargazersCount を一通り持たせている）
        //
        // 生成される Repo の例:
        // - id: "repos/0"
        // - fullName: "repos/0"
        // - description: "my awesome project"
        // - language: "swift"
        // - stargazersCount: 0
        //
        // id は GitHubRepo.ID という型で包まれており、
        // 単なる String を渡すよりも “Repo ID である” ことが明確になる。
        let repos = (0..<5).map { i in
            GitHubRepo(
                id: GitHubRepo.ID(rawValue: "repos/\(i)"),
                fullName: "repos/\(i)",
                description: "my awesome project",
                language: "swift",
                stargazersCount: i
            )
        }

        // completion を呼んで結果を返す。
        // 本物のネットワーク実装は非同期で返るが、スタブは即座に返してもよい。
        // ただし “非同期性” を再現したい場合は DispatchQueue.main.async / asyncAfter を使う選択肢もある。
        completion(.success(repos))
    }
}

//
// MARK: - スタブをより実務寄りにする改善案（必要に応じて）
//
// 1) keywords を使って返す内容を変える
//    - keywords が空なら failure を返す
//    - keywords によって repo 件数や名前を変える
//
// 2) エラー系スタブを作る
//    - 常に failure を返す
//    - 特定キーワードでのみ failure を返す
//
// 3) 非同期性を再現する
//    - completion を DispatchQueue.global().asyncAfter(...) で遅延させる
//    - UI のローディング表示やタイムアウト挙動の検証ができる
//```