//
//  GitHubRepo.swift
//  CleanGitHub
//
//
//  このファイルは Clean Architecture（クリーンアーキテクチャ）における Entity（エンティティ）を表す。
//  Entity は “ビジネスルールの中心” に位置する概念であり、以下の特徴を持つのが理想である。
//
//  - アプリの最重要データ（ドメイン概念）を表現する
//  - 画面（UI）やネットワーク、DB といった外部要因から独立している
//  - どんなフレームワークを使っても意味が崩れない（UIKit / Alamofire / Realm 等に依存しない）
//  - 変更に強い（外側の都合が変わっても Entity は変わりにくい）
//
//  ただし、実装上は “Codable に準拠している” ため、APIレスポンスや永続化との境界が近い可能性がある。
//  Clean Architecture 的には、Entity は本来「外部フォーマット（JSON）とは無関係」に保ち、
//  - APIのDTO（Data Transfer Object）
//  - 永続化用モデル
//  から Entity へ変換する層（Mapper）を置くのがより純粋である。
//  とはいえ、小〜中規模では Entity を Codable にして実装コストを下げる判断も現実的であり、
//  このコードは “ドメインの中心データ” としての形を十分に備えている。
//
//  この Entity が表すドメイン概念:
//    GitHub 上のリポジトリ（Repo）
//  であり、ID・表示名・説明・主要言語・スター数といった、ユースケースで重要になりやすい属性を持つ。
//

import Foundation

// MARK: - Entity: GitHubRepo
//
// struct にしているため値型（immutable寄り）として扱いやすい。
// Entity は「状態の一貫性」を保ちたいので、値型 + let プロパティは相性が良い。
//
// Equatable:
// - “同一性（Identity）” の比較を定義するために利用される
// - ここでは id が同じなら同一Repoと見なす（後述）
//
// Codable:
// - JSON/永続化との変換を容易にするための仕組み
// - Clean Architecture 的には境界層で DTO に Codable を持たせる方が理想だが、
//   実用上 Entity に持たせる設計もある（トレードオフ）
struct GitHubRepo: Equatable, Codable {

    // MARK: - Identity (Entity の “同一性”)
    //
    // Clean Architecture における Entity の重要概念は「同一性（Identity）」である。
    // Entity は属性が変わっても “同じ存在” とみなせる必要がある。
    //
    // 例:
    // - description が更新された
    // - stargazersCount が増えた
    // それでも「同じリポジトリ」である。
    //
    // そのため、Entity は “識別子” を持ち、それで同一性を判断する。
    //
    // ここでは GitHubRepo.ID を設けて id を型として強くしているのがポイント。

    /// GitHubRepo の識別子型。
    /// RawRepresentable により内部的には String を保持するが、単なる String と区別できる。
    ///
    /// これにより、
    /// - RepoのID と UserのID を混同する
    /// - どこから来た String か分からない
    /// といった “プリミティブ型の混乱（Primitive Obsession）” を避けられる。
    ///
    /// Hashable:
    /// - Set や Dictionary のキーに使える（同一性に基づく集合操作ができる）
    ///
    /// Codable:
    /// - エンコード/デコード対象として扱える
    struct ID: RawRepresentable, Hashable, Codable {
        /// 識別子の実体。APIの仕様上 String であると仮定している。
        /// 本当に数値IDなら Int にする方が自然だが、外部仕様に合わせた型選択になる。
        let rawValue: String
    }

    /// Entity の同一性を表す主キー（Identity）。
    /// ここが Entity としての “核” になる。
    let id: ID

    // MARK: - Attributes (Entity の属性)
    //
    // Entity は同一性（id）と属性（ビジネス上意味のあるデータ）で構成される。
    // ここにある属性は “ユースケースで必要な情報” として選ばれている想定。

    /// GitHub上のフルネーム（例: "apple/swift"）。
    /// 表示名や検索結果表示で頻繁に使われる。
    let fullName: String

    /// リポジトリの説明文。
    /// UI表示用に使われることが多いが、ドメインとしても “Repoの概要” という意味を持つ。
    /// 実務では description が nil のケースがあるため Optional にする検討余地がある。
    let description: String

    /// 主要言語。
    /// フィルタリングやタグ表示に利用される。
    /// GitHub API では nil の場合もあるので Optional を検討することがある。
    let language: String

    /// スター数。
    /// 数値のランキングや人気判定など、ユースケースで使われやすい。
    let stargazersCount: Int

    // MARK: - Equatable (同一性に基づく等価性)
    //
    // Entity の Equatable は「属性がすべて一致するか」ではなく、
    // “同一性が一致するか（同じ存在か）” で定義することが多い。
    //
    // この実装はまさにそれで、id が一致すれば同じ Repo とみなす。
    // たとえスター数や説明文が変わっていても “同じRepo” である、というドメインルールを反映している。
    public static func == (lhs: GitHubRepo, rhs: GitHubRepo) -> Bool {
        return lhs.id == rhs.id
    }
}

//
// MARK: - Clean Architecture 的補足（Entityとしてさらに純粋にするなら）
//
// 1) Entity から Codable を外し、DTO を別に作る
//    - GitHubRepoDTO: Codable（APIレスポンス用）
//    - GitHubRepo: Entity（純粋なドメイン型）
//    - Mapper: DTO -> Entity
//
//    こうすると “外部仕様の変化（JSONキー変更など）” が Entity に波及しにくくなる。
//
// 2) Optional の扱い（外部データの欠損）
//    GitHub API では description/language が欠損することがある。
//    Entity 側で Optional にするか、Mapper で空文字に正規化するかはユースケース次第。
//    Clean Architecture 的には “ドメインで自然な形” に正規化して持つのが望ましい。
//
// 3) 値オブジェクトの導入
//    fullName や language を Value Object として型を強くすると、
//    ドメインルール（例: fullName は "owner/name" 形式）を閉じ込められる。
//```