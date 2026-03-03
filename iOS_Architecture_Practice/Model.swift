//
//  Model.swift
//  RxSimpleSample
//
//
//  このファイルは「入力検証（Validation）」のドメインロジックを担う Model 層である。
//  ViewModel は UI 表示（テキスト/色）に寄った “プレゼンテーション変換” を担当し、
//  Model は「id/password が妥当かどうか」という判定だけを返すように分離されている。
//
//  この Model のアルゴリズムは、入力 (idText?, passwordText?) を受け取り、
//  次のいずれかの結果を返す関数 validate を提供する。
//    - success(())                   : 両方の入力が妥当
//    - failure(ModelError.XXX)       : 未入力/空文字などで不正
//
//  ここでの “妥当性” の定義はサンプルとして単純で、
//  - nil（未入力）と空文字（""）を「未入力」として扱う
//  - id と password の両方が非空なら OK
//  というルールになっている。
//
//  重要なのは、Model は UI のこと（色や表示文言）を一切知らない点である。
//  エラー種別だけ返し、表示への変換は ViewModel 側で行うことで層が綺麗に分かれる。
//

import Foundation

// MARK: - Result<T>
//
// 独自定義の Result 型。
// Swift 標準の Result<T, Error> と同じ目的を持つが、このサンプルでは簡略化のため自前実装している。
//
// 仕様:
// - success(T): 成功し、値 T を持つ
// - failure(Error): 失敗し、Error を持つ
//
// 実務では Swift 標準の Result を使う方が一般的である。
// ただし教材としては「success/failure の二分」を明示できる利点がある。
enum Result<T> {
    case success(T)
    case failure(Error)
}

// MARK: - ModelError
//
// validate が返しうる “失敗理由” を表すエラー型。
// UI が必要とする情報はここでは持たない（文言や色は ViewModel で決める）。
enum ModelError: Error {

    /// id が未入力/空
    case invalidId

    /// password が未入力/空
    case invalidPassword

    /// id と password の両方が未入力/空
    case invalidIdAndPassword
}

// MARK: - ModelProtocol
//
// Model のインターフェース。
// ViewModel は具象の Model に依存せず、このプロトコルに依存することでテスト差し替えを可能にする。
protocol ModelProtocol {

    /// id/password の妥当性を検証する。
    ///
    /// - Parameters:
    ///   - idText: ID の入力（nil は未入力とみなす）
    ///   - passwordText: Password の入力（nil は未入力とみなす）
    ///
    /// - Returns:
    ///   - .success(())                         : 妥当（両方とも非空）
    ///   - .failure(ModelError.invalidId...)    : 不正（未入力/空）
    ///
    /// ※ この validate は “純粋関数” 的に振る舞うことが重要であり、
    ///    副作用（通知、UI更新、保存など）を持たないのが望ましい。
    func validate(idText: String?, passwordText: String?) -> Result<Void>
}

// MARK: - Model
//
// validate の具体実装。
// この関数は入力の組み合わせを網羅して、適切な ModelError を返す。
final class Model: ModelProtocol {

    /// id/password の検証。
    ///
    /// アルゴリズム（分岐戦略）:
    /// 1) まず Optional の状態（nil / some）で大きく分岐する
    /// 2) 両方 some の場合のみ、さらに isEmpty を見て “空文字” を未入力として扱う
    ///
    /// ここで (idText, passwordText) をタプルとして switch しているため、
    /// “入力状態の組み合わせ” を網羅しやすい。
    func validate(idText: String?, passwordText: String?) -> Result<Void> {

        // Optional の組み合わせをまず判定する。
        switch (idText, passwordText) {

        case (.none, .none):
            // id も password も nil（どちらも未入力）
            return .failure(ModelError.invalidIdAndPassword)

        case (.none, .some):
            // id が nil、password は some（id が未入力）
            // password が空文字かどうかはここではまだ不問（some なので次の段階で扱う設計もあり得るが、
            // このサンプルでは password が some なら “入力された” と見なしている）
            return .failure(ModelError.invalidId)

        case (.some, .none):
            // id は some、password が nil（password が未入力）
            return .failure(ModelError.invalidPassword)

        case (let idText?, let passwordText?):
            // 両方 some（文字列が存在する）なので、次に空文字チェックを行う。
            // ここで nil と "" を同等に扱うために、isEmpty を見ている。
            switch (idText.isEmpty, passwordText.isEmpty) {

            case (true, true):
                // 両方空文字 → 両方未入力扱い
                return .failure(ModelError.invalidIdAndPassword)

            case (false, false):
                // 両方非空 → 妥当
                // 成功値は Void なので () を返す（値は意味を持たず “成功した” 事実のみを表す）
                return .success(())

            case (true, false):
                // id が空、password は非空 → id 未入力扱い
                return .failure(ModelError.invalidId)

            case (false, true):
                // id は非空、password が空 → password 未入力扱い
                return .failure(ModelError.invalidPassword)
            }
        }
    }
}

// MARK: - 実務向け補足（改善の方向性）
//
// 1) nil と "" を同等扱いするなら、先に正規化すると読みやすい
//    例：
///       let id = idText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
//       let pw = passwordText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
//       そして id.isEmpty / pw.isEmpty の4パターンだけを判定する
//
// 2) Result は Swift標準の Result<Void, ModelError> を使うと型安全になる
//    今は failure が Error なので、ModelError 以外が紛れ込む余地がある
//
// 3) エラーメッセージは ModelError に直接持たせず ViewModel 側で変換するのが良い
//    本サンプルはその方針で正しい