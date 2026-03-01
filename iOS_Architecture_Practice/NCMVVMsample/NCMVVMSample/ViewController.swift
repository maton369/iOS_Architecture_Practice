//
//  ViewController.swift
//  RxSimpleSample
//
//  このサンプルは「Rx（Reactive）っぽい」考え方を、RxSwift/Combine を使わずに
//  NotificationCenter で再現した最小例である。
//
//  重要な構造は以下。
//  - ViewController は UIイベント（TextFieldの編集）を ViewModel に渡す
//  - ViewModel は入力（id/password）を検証し、結果（文字列/色）の更新イベントを発火する
//  - ViewController はそのイベントを購読して UILabel を更新する
//
//  つまりデータフローは
//
//    UI入力(TextField) → ViewModel(検証/状態計算) → 通知(Notification) → UI出力(Label更新)
//
//  となり、「状態が変わったら通知でUIが変わる」というリアクティブの基本形を手作りしている。
//  Rx/Combine と違って “購読解除の管理” を自分でやる必要がある点が落とし穴になりやすい。
//

import UIKit

// MARK: - View (UIViewController)
//
// final にすることで継承による振る舞い変更を防ぎ、画面ロジックを固定する。
// ここでの ViewController の主な責務は次の2つ。
//  (1) UIイベントを捕捉して ViewModel へ入力として渡す（入力側）
//  (2) ViewModel からの変更通知を購読して UI を更新する（出力側）
final class ViewController: UIViewController {

    // MARK: UI Outlets

    /// ユーザID入力欄。
    /// .editingChanged イベントを拾って ViewModel に反映する。
    @IBOutlet private weak var idTextField: UITextField!

    /// パスワード入力欄。
    /// .editingChanged イベントを拾って ViewModel に反映する。
    @IBOutlet private weak var passwordTextField: UITextField!

    /// 入力が妥当かどうか（またはその理由）を表示するラベル。
    /// ViewModel からの通知により text と textColor が更新される。
    @IBOutlet private weak var validationLabel: UILabel!

    // MARK: Reactive-ish Event Bus

    /// この画面で使う通知センター。
    /// NotificationCenter.default ではなく独自インスタンスを持つことで、
    /// 通知のスコープが「この画面/この ViewModel」に閉じ、衝突や外部干渉を防ぎやすい。
    ///
    /// ただし実務では、NotificationCenter は “グローバルイベント” 用に使われがちなので、
    /// ローカルイベントバスとして使う設計はチーム内合意が必要になることが多い。
    private let notificationCenter = NotificationCenter()

    // MARK: ViewModel

    /// ViewModel は「入力(id/password)」を受けて「出力（検証メッセージ/色）」を計算する想定。
    /// 通知センターを注入しているため、ViewModel は通知の発火を担当する。
    ///
    /// lazy にしている理由:
    /// - notificationCenter が初期化された後に ViewModel を作りたい
    /// - 画面起動時にすぐ使うので通常は即生成と同義
    private lazy var viewModel = ViewModel(
        notificationCenter: notificationCenter
    )

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // --- 1) UI入力イベントの配線（TextField -> ViewController） ---
        // テキストが変わるたびに textFieldEditingChanged が呼ばれる。
        // これを ViewModel へ入力として渡すことで、リアルタイム検証が可能になる。
        idTextField.addTarget(
            self,
            action: #selector(textFieldEditingChanged),
            for: .editingChanged
        )
        passwordTextField.addTarget(
            self,
            action: #selector(textFieldEditingChanged),
            for: .editingChanged
        )

        // --- 2) ViewModel 出力イベントの購読（ViewModel -> Notification -> ViewController） ---
        // ViewModel が発火する通知（changeText/changeColor）を購読して UI を更新する。
        //
        // selector ベースの addObserver は “self” を observer として登録する旧式API。
        // この場合、deinit で removeObserver(self) するのが定石。
        // （iOS 9以降は自動解除されるケースもあるが、挙動に依存すると保守しづらいので明示解除が安全）
        notificationCenter.addObserver(
            self,
            selector: #selector(updateValidationText),
            name: viewModel.changeText,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(updateValidationColor),
            name: viewModel.changeColor,
            object: nil
        )

        // NOTE（実務的注意）:
        // - ここで observer を登録しているが、解除処理（deinit / viewWillDisappear 等）が無い。
        //   ローカル NotificationCenter を使っているので leak は起こりにくいが、
        //   “通知が残って予期せぬ呼び出し” を避けるため、removeObserver を入れるのが安全。
        //
        // 例:
        // deinit { notificationCenter.removeObserver(self) }
    }
}

// MARK: - Input/Output handlers
//
// ViewController の役割は「入力を ViewModel に渡す」「出力を UI に適用する」だけに分けると読みやすい。
// 下の extension はその整理になっている。
extension ViewController {

    // MARK: Input (UI -> ViewModel)

    /// TextField の編集が変化するたびに呼ばれる。
    ///
    /// sender がどちらの TextField かは本質ではなく、
    /// 画面全体の入力状態（idTextField.text と passwordTextField.text）を ViewModel に渡して再評価させる。
    ///
    /// アルゴリズム:
    /// 1) 現在の id/password の文字列を取得（Optional）
    /// 2) ViewModel に「入力が変わった」ことを通知
    /// 3) ViewModel が検証し、必要なら changeText/changeColor 通知を発火
    @objc func textFieldEditingChanged(sender: UITextField) {
        viewModel.idPasswordChanged(
            id: idTextField.text,
            password: passwordTextField.text
        )
    }

    // MARK: Output (ViewModel -> UI)

    /// 検証メッセージ更新通知を受け、UILabel の text を更新する。
    ///
    /// この実装では Notification.object に String を詰める設計。
    /// - 型安全性は低い（Any になる）
    /// - しかしサンプルとしては「イベントで値を運ぶ」を最小に表現できる
    ///
    /// 実務では userInfo のキーを定数化する、または Combine/Rx の型付きストリームを使うのが一般的。
    @objc func updateValidationText(notification: Notification) {
        guard let text = notification.object as? String else { return }
        validationLabel.text = text
    }

    /// 検証状態に応じた色更新通知を受け、UILabel の textColor を更新する。
    /// Notification.object に UIColor を詰める設計。
    @objc func updateValidationColor(notification: Notification) {
        guard let color = notification.object as? UIColor else { return }
        validationLabel.textColor = color
    }
}

// MARK: - 実務向け補足（この設計の落とし穴）
//
// 1) “通知名” と “payload” が型安全でない
//    - Notification.Name が散らばると衝突やtypoが起きやすい
//    - object に Any を詰めると型ミスが実行時まで分からない
//
// 2) ライフサイクルと購読解除
//    - selector型 addObserver は removeObserver が必要になりやすい
//    - 画面遷移や再生成で二重登録が起きると、更新が重複する
//
// 3) Combine/Rx で置き換えるなら
//    - TextField の入力を Publisher/Observable にし
//    - ViewModel が validationText/validationColor を出力
//    - View が bind する
//   という形にすると “通知の手動管理” を減らせる