//
//  ViewModel.swift
//  RxSimpleSample
//
//
//  この ViewModel は「リアクティブな入力→出力」を NotificationCenter で表現するための中核である。
//  RxSwift/Combine を使うなら Observable/Publisher を返すところだが、このサンプルでは
//  “イベント（通知）を発火する” ことで View（ViewController）へ結果を伝えている。
//
//  アルゴリズムの大枠は次の通り。
//    1) View から id/password の変更通知（idPasswordChanged）が呼ばれる
//    2) Model に入力を渡して validate を実行する（純粋に判定）
//    3) 判定結果に応じて、表示すべきテキストと色を決める
//    4) changeText / changeColor の2種類の通知を発火し、View を更新させる
//
//  つまり ViewModel は
//    入力（Optional<String>）→ 状態判定（Model）→ 出力（Text/Colorイベント）
//  の変換器（Transformer）である。
//

import UIKit

// MARK: - ViewModel
//
// final: 継承で仕様が変わると通知名や出力契約が壊れやすいので固定する意図。
// ここでは ViewModel が “イベント発火” まで担当しているため、出力契約が特に重要になる。
final class ViewModel {

    // MARK: Output event names (ViewModel -> View)

    /// 検証結果テキストを更新してほしい、という通知名。
    /// ViewController はこの name を購読し、Notification.object を String として解釈して表示更新する。
    ///
    /// 注意点:
    /// - Notification.Name は文字列ベースなので typo に弱い
    /// - 可能なら static let にして集約すると良い
    /// - あるいは Combine/Rx に移行すると型安全になる
    let changeText = Notification.Name("changeText")

    /// 検証結果の色を更新してほしい、という通知名。
    /// ViewController は Notification.object を UIColor として解釈して textColor を更新する。
    let changeColor = Notification.Name("changeColor")

    // MARK: Dependencies

    /// 通知を流すための NotificationCenter。
    /// ViewController と同一インスタンスを使うことで、通知のスコープを「この画面」に閉じられる。
    /// default を使うより衝突しにくいが、購読解除などのライフサイクル管理は依然として必要。
    private let notificationCenter: NotificationCenter

    /// 入力検証ロジック（ドメイン/モデル層）。
    /// ViewModel は UI 依存（UIKit）を避けたいが、このサンプルでは出力色に UIColor を使うため UIKit 依存が残る。
    /// validate 自体は UI に依存しない純粋関数に寄せるのが望ましい。
    private let model: ModelProtocol

    // MARK: Init (DI)

    /// DI（依存注入）で NotificationCenter と Model を受け取る。
    ///
    /// - notificationCenter: View と共有するイベントバス
    /// - model: 検証ロジック（デフォルトは Model()）
    ///
    /// テストでは ModelProtocol をモックに差し替えられるので、
    /// ViewModel の変換ロジック（Result → 通知内容）をネットワークやUI無しで検証できる。
    init(notificationCenter: NotificationCenter, model: ModelProtocol = Model()) {
        self.notificationCenter = notificationCenter
        self.model = model
    }

    // MARK: Input (View -> ViewModel)

    /// View から「id/password が変わった」と通知される入口。
    ///
    /// アルゴリズム:
    /// 1) Model.validate に入力を渡して Result を得る
    /// 2) success のとき: "OK!!!" + 緑
    /// 3) failure(ModelError) のとき: エラーメッセージ + 赤
    /// 4) 上記を NotificationCenter 経由で View に配信する
    ///
    /// ここでの設計は “出力が2系統（textとcolor）” である点が特徴。
    /// 実務では (text, color) を1つの状態としてまとめて通知する設計も多い。
    func idPasswordChanged(id: String?, password: String?) {

        // --- 1) 入力を検証 ---
        // validate は「入力の妥当性」を判定するだけの処理で、UI更新はここでは行わない。
        let result = model.validate(idText: id, passwordText: password)

        // --- 2) 判定結果から出力を決定し、イベントとして発火 ---
        // ViewModel は “結果の解釈” を行い、View がそのまま表示できる形（テキスト/色）に落とす。
        switch result {

        case .success:
            // 成功時は OK 表示と緑色。
            // ここでは notification.object に値を直接載せている（Any）ため型安全ではない。
            // guard/cast に失敗すると View 側は更新されないので、実務では userInfo + key 定数化が望ましい。
            notificationCenter.post(name: changeText, object: "OK!!!")
            notificationCenter.post(name: changeColor, object: UIColor.green)

        case .failure(let error as ModelError):
            // ModelError の場合だけメッセージを生成して表示する。
            // errorText は下の extension で UI向け文言へ変換している。
            notificationCenter.post(name: changeText, object: error.errorText)
            notificationCenter.post(name: changeColor, object: UIColor.red)

        case _:
            // 想定外の failure（ModelError 以外）が来た場合は即落とす。
            // これは “サンプルとして分かりやすくするため” だが、実務では次のいずれかが望ましい。
            // - すべての Error を網羅してユーザ向け表示に変換する
            // - ログ収集しつつ、汎用エラーメッセージを表示する
            // - fatalError は避け、fail-safe に倒す
            fatalError("Unexpected pattern.")
        }
    }
}

// MARK: - Presentation mapping (ModelError -> user-facing text)
//
// ModelError を UI に表示する文章へ変換する層。
// “モデルのエラー型” を “プレゼンテーション文字列” に落とす責務は、ViewModel に置くのが自然。
// （View が判断を持つと UI 層が肥大化し、Model が文字列を持つとドメインが UI に侵食されるため）
extension ModelError {

    /// UI 向けのエラーメッセージ。
    /// fileprivate にしているのは、このファイル内（ViewModelの文脈）でのみ使う意図。
    ///
    /// 注意:
    /// - 文言はローカライズ対象になりやすいので、実務では Localizable.strings 等へ移すことが多い。
    /// - ここに “表示文言” を置くことで、ViewController 側は単に受け取って表示するだけになる。
    fileprivate var errorText: String {
        switch self {
        case .invalidIdAndPassword:
            return "IDとPasswordが未入力です。"
        case .invalidId:
            return "IDが未入力です。"
        case .invalidPassword:
            return "Passwordが未入力です。"
        }
    }
}