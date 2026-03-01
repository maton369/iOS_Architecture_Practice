//
//  ViewController.swift
//  CocoaMVCSample
//
//
//  このサンプルは、いわゆる「Cocoa MVC（UIKit MVC）」の典型形を示している。
//  つまり “UIViewController が Controller であり、View と Model を仲介する中心” になる構造である。
//
//  原初MVC（Smalltalk MVC）との対比で見ると、ここでは ViewController が次を全部担う：
//    - View の生成/保持（loadView）
//    - View へのイベントハンドラ登録（addTarget）
//    - Model の操作（countUp / countDown 呼び出し）
//    - Model の変更監視（NotificationCenter observer）
//    - View の更新（label.text を更新）
//
//  その結果、処理の流れは「入力（UI）→ ViewController → Model → 通知 → ViewController → View」となる。
//  Cocoaフレームワークの設計に沿った自然な形だが、規模が大きくなると ViewController が肥大化しやすい
//  （いわゆる Massive ViewController）という問題にも繋がる。
//  ただし、このサンプルは最小例として “Cocoa MVC のデータフロー” を理解する教材として優れている。
//

import UIKit

// MARK: - ViewController (Cocoa MVC の中心)
//
// Cocoa MVC における ViewController は、MVC の "C（Controller）" を担うと同時に、
// UIKit の画面ライフサイクル管理の中心でもある。
// そのため、本実装では ViewController が Model と View を直接結び付け、イベントも監視も担当している。
class ViewController: UIViewController {

	// MARK: Model Injection / Binding

	/// 画面に紐付く Model。
	/// 外部（Composition Root）から注入される想定で、セットされた瞬間に View と結線する。
	///
	/// didSet で registerModel() を呼ぶことで、
	///   - UI の初期表示
	///   - ボタンイベントの配線
	///   - Model 変更通知の購読開始
	/// を一括で開始する。
	///
	/// 注意点:
	/// - didSet は「同じModelを再代入」しても呼ばれるため、二重登録が起きうる。
	///   実用では「既存 observer を解除してから再登録」や「登録済みガード」が必要になることが多い。
	var myModel: Model? {
		didSet { // ViewとModelとを結合し、Modelの監視を開始する
			registerModel()
		}
	}

	// MARK: View Ownership

	/// 画面の root view。
	/// lazy にすることで「初回アクセス時に生成」する。
	/// loadView で view に代入するので、Storyboard を使わないコードベースUIの基本形。
	private(set) lazy var myView: View = View()

	override func loadView() {
		/// UIKit は view プロパティを root view として使う。
		/// ここで自前 View を割り当てる。
		view = myView
	}

	deinit {
		/// Model 側 NotificationCenter から observer を解除する意図。
		///
		/// ただし本コードは addObserver(forName:object:queue:using:) を使用しているため、
		/// 解除には「戻り値のトークン（NSObjectProtocol）を保持して removeObserver(token)」が推奨される。
		/// removeObserver(self) は旧API（selector型）では有効だが、ここでは効かない/不完全になる可能性がある。
		///
		/// 実用化するなら：
		///   - var observerToken: NSObjectProtocol?
		///   - observerToken = notificationCenter.addObserver(...)
		///   - deinit { if let t = observerToken { removeObserver(t) } }
		/// とするのが安全。
		myModel?.notificationCenter.removeObserver(self)
	}

	// MARK: Binding logic (View <-> Model)

	/// Model が注入されたタイミングで、View と Model を結線する。
	/// Cocoa MVC の中心ロジックであり、ここが肥大化しやすいポイントでもある。
	private func registerModel() {

		guard let model = myModel else { return }

		// --- 1) UI 初期表示 ---
		// Model の現在状態を View に反映して、画面を正しい状態からスタートさせる。
		myView.label.text = model.count.description

		// --- 2) UI イベントを ViewController に配線 ---
		// UIKit の典型：View のイベントは Controller(ViewController) が受ける。
		// ここが原初MVCと違う点で、ViewControllerがイベント受信点になる。
		myView.minusButton.addTarget(self, action: #selector(onMinusTapped), for: .touchUpInside)
		myView.plusButton.addTarget(self, action: #selector(onPlusTapped), for: .touchUpInside)

		// --- 3) Model 変更通知を購読して View を更新 ---
		// Model の count が変わったら UI を更新する。
		//
		// 注意点（実務でバグになりやすい）:
		// - queue: nil の場合、通知コールバックは投稿側スレッドで動く可能性がある。
		//   UI 更新は main thread 必須なので queue: .main を指定するのが安全。
		// - [unowned self] は self が解放済みだとクラッシュする。
		//   ここでは ViewController のライフサイクル中に通知が来る前提だが、念のため [weak self] が無難。
		// - さらに、registerModel が複数回呼ばれると observer が複数登録され、UI更新が重複する可能性がある。
		model.notificationCenter.addObserver(
			forName: .init(rawValue: "count"),
			object: nil,
			queue: nil,
			using: { [unowned self] notification in
				if let count = notification.userInfo?["count"] as? Int {
					// Model → ViewController → View という経路で UI を更新する。
					self.myView.label.text = "\(count)"
				}
			}
		)
	}

	// MARK: - Event Handlers (UI → Model)

	/// -1 ボタンが押されたら Model を操作する。
	/// Cocoa MVC の基本：イベントは ViewController が受け、Model を更新する。
	@objc func onMinusTapped() {
		myModel?.countDown()
	}

	/// +1 ボタンが押されたら Model を操作する。
	@objc func onPlusTapped() {
		myModel?.countUp()
	}
}

// MARK: - Model
//
// Model はアプリ状態（count）と、その状態を変える操作（countUp / countDown）を持つ。
// 状態変化は NotificationCenter を通じて外部へ通知する（Observerパターン）。
class Model {

	/// Model 専用の NotificationCenter を保持する。
	/// default を使わないのは「この Model の世界に通知を閉じる」意図があると考えられる。
	/// ただし実務では Combine / delegate / closure 等の方が型安全で追跡も容易。
	let notificationCenter = NotificationCenter()

	/// 外部からは読み取りのみ可能にして、書き換えはメソッド経由に限定する。
	/// これにより Model のルール（不変条件）を守りやすくなる。
	private(set) var count = 0 {
		didSet {
			/// count が変化したら通知を発火する。
			/// userInfo で値を運ぶため型安全ではない（Stringキー & Any）。
			/// 実用では Notification.Name と userInfo キーの定数化が推奨。
			notificationCenter.post(
				name: .init(rawValue: "count"),
				object: nil,
				userInfo: ["count": count]
			)
		}
	}

	/// count を 1 減らす操作。
	/// 0 未満禁止などの制約があるなら、この層でガードするのが自然。
	func countDown() {
		count -= 1
	}

	/// count を 1 増やす操作。
	func countUp() {
		count += 1
	}
}

// MARK: - View
//
// View は「見た目の部品（UILabel/UIButton）」と「レイアウト」を担当する。
// Cocoa MVC では View は基本的に “受動的” で、イベント処理や状態管理を持たない。
// 本実装でも、View はイベントを持たず、UI部品を提供するだけになっている。
class View: UIView {

	// MARK: UI components

	/// カウント表示用ラベル
	let label = UILabel()

	/// -1 ボタン（イベント処理は ViewController 側）
	let minusButton = UIButton()

	/// +1 ボタン（イベント処理は ViewController 側）
	let plusButton = UIButton()

	// MARK: Init

	override init(frame: CGRect) {
		super.init(frame: frame)
		setSubviews()
		setLayout()
	}

	required init?(coder aDecoder: NSCoder) {
		/// Storyboard 非対応のため nil。
		/// 実務では fatalError の方が意図が明確なケースが多い。
		return nil
	}

	// MARK: UI Setup

	private func setSubviews() {

		addSubview(label)
		addSubview(minusButton)
		addSubview(plusButton)

		label.textAlignment = .center

		// サンプル用の視覚的区別（本番UIではデザインシステムに寄せる）
		label.backgroundColor = .blue
		minusButton.backgroundColor = .red
		plusButton.backgroundColor = .green

		minusButton.setTitle("-1", for: .normal)
		plusButton.setTitle("+1", for: .normal)
	}

	private func setLayout() {

		// AutoLayout をコードで使うための定石
		label.translatesAutoresizingMaskIntoConstraints = false
		plusButton.translatesAutoresizingMaskIntoConstraints = false
		minusButton.translatesAutoresizingMaskIntoConstraints = false

		// レイアウト構造：
		//  上段：label
		//  下段：[-1][+1] ボタンが左右に並ぶ
		label.topAnchor.constraint(equalTo: topAnchor).isActive = true
		label.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
		label.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
		label.bottomAnchor.constraint(equalTo: minusButton.topAnchor).isActive = true
		label.bottomAnchor.constraint(equalTo: plusButton.topAnchor).isActive = true
		label.heightAnchor.constraint(equalTo: minusButton.heightAnchor).isActive = true
		label.heightAnchor.constraint(equalTo: plusButton.heightAnchor).isActive = true

		minusButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
		plusButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
		minusButton.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
		minusButton.rightAnchor.constraint(equalTo: plusButton.leftAnchor).isActive = true
		plusButton.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
		minusButton.widthAnchor.constraint(equalTo: plusButton.widthAnchor).isActive = true
	}
}