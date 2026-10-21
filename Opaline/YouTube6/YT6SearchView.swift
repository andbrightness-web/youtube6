import UIKit

/// What the search bar reports to `YT6Search` (`YTSearchViewDelegate`).
protocol YT6SearchViewDelegate: AnyObject {
    func searchViewQueryDidChange(_ query: String)
    func searchViewDidSubmit(_ query: String)
    func searchViewDidAppend(_ suggestion: String)
    func searchViewCanDelete(_ suggestion: String) -> Bool
    func searchViewDelete(_ suggestion: String)
}

/// `YTSearchView_iPhone`: the 2.0.0 search bar. Not a screen — one view over
/// the content and its title bar. Focused, the bar sits where the title bar
/// is, the content dims under a black shield at 0.667 and the suggestions
/// hang under the bar; unfocused, bar and suggestions sit above the top edge
/// and the view hides (`layoutSubviews` @73838, `gainFocus` @73dac,
/// `loseFocus` @73eec). No voice button (not built) and no Cancel: a tap on
/// the shield closes it (`shieldDidReceiveTouch:` @74440).
final class YT6SearchView: UIView {
    /// `-[YTNavigation_iPhone runAppWithWindow:]` @2329e: the title bar's
    /// height.
    static let barHeight: CGFloat = 44
    /// `layoutSubviews` @739b8: the field plate is 14 pt narrower.
    static let fieldPlateInset: CGFloat = 14
    /// `-[GIPInputShieldView initWithFrame:]` @1511b4.
    static let shieldAlpha: CGFloat = 0.667
    /// `gainFocus` @73e26 / `loseFocus` @73f76 / `setSuggestions:` @73c9c.
    static let duration: TimeInterval = 0.25

    weak var delegate: YT6SearchViewDelegate?
    let field = YT6SearchField()
    private(set) var suggestions: [String] = []
    private(set) var hasFocus = false
    private let shield = UIControl()
    private let table = UITableView(frame: .zero, style: .plain)
    private let barBackground = UIImageView(image: YT6.stretchableImage("search_titlebar"))
    private let fieldPlate = UIImageView(image: YT6.stretchableImage("search_input"))
    private var keyboardHeight: CGFloat = 0

    /// `-[YTSearchView_iPhone query]` @73cf0: the text, trimmed.
    var query: String {
        (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        clipsToBounds = true
        shield.backgroundColor = .black
        shield.alpha = 0
        shield.addTarget(self, action: #selector(loseFocus), for: .touchDown)
        setUpTable()
        field.delegate = self
        field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        [shield, table, barBackground, fieldPlate, field].forEach(addSubview)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidShow(_:)),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bar = CGRect(
            x: 0, y: hasFocus ? 0 : -Self.barHeight, width: bounds.width, height: Self.barHeight
        )
        shield.frame = bounds
        shield.alpha = hasFocus ? Self.shieldAlpha : 0
        field.frame = bar
        let plateHeight = fieldPlate.image?.size.height ?? 0
        fieldPlate.frame = CGRect(
            x: (Self.fieldPlateInset / 2).rounded(),
            y: (bar.midY - plateHeight / 2).rounded(),
            width: bar.width - Self.fieldPlateInset,
            height: plateHeight
        )
        barBackground.frame = bar
        layoutSuggestions()
    }

    func gainFocus() {
        layoutIfNeeded()
        hasFocus = true
        UIView.animate(withDuration: Self.duration) {
            self.isHidden = false
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        field.becomeFirstResponder()
    }

    @objc
    func loseFocus() {
        layoutIfNeeded()
        hasFocus = false
        UIView.animate(
            withDuration: Self.duration,
            animations: {
                self.setNeedsLayout()
                self.layoutIfNeeded()
            },
            completion: { _ in
                self.isHidden = !self.hasFocus
            }
        )
        field.resignFirstResponder()
    }

    func setSuggestions(_ items: [String]) {
        suggestions = items
        table.reloadData()
        UIView.animate(withDuration: Self.duration) {
            self.layoutSuggestions()
        }
    }

    /// `layoutSuggestionsView` @73aac: as many 36 pt rows as fit above the
    /// keyboard less one, right under the bar; above the top edge when
    /// unfocused.
    private func layoutSuggestions() {
        let rowHeight = YT6SearchSuggestionCell.height
        let room = bounds.height - keyboardHeight - Self.barHeight
        let fitting = max((room / rowHeight - 1).rounded(.down), 0)
        let height = min(fitting, CGFloat(suggestions.count)) * rowHeight
        table.frame = CGRect(
            x: 0, y: hasFocus ? Self.barHeight : -height, width: bounds.width, height: height
        )
    }

    private func setUpTable() {
        table.dataSource = self
        table.delegate = self
        table.scrollsToTop = false
        table.rowHeight = YT6SearchSuggestionCell.height
        // APPROXIMATION: iOS 6 plain-table separators ran edge to edge.
        table.separatorInset = .zero
        table.register(
            YT6SearchSuggestionCell.self,
            forCellReuseIdentifier: YT6SearchSuggestionCell.reuseId
        )
    }

    @objc
    private func editingChanged() {
        delegate?.searchViewQueryDidChange(query)
    }

    /// `keyboardDidShow:` @74508 keeps the keyboard height for the rows.
    @objc
    private func keyboardDidShow(_ note: Notification) {
        let frame = note.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect
        keyboardHeight = frame?.height ?? 0
        setNeedsLayout()
    }

    /// `didPressAppend:` @74318: the row is found from the button's place.
    @objc
    private func appendPressed(_ sender: UIButton) {
        let point = table.convert(sender.bounds.origin, from: sender)
        guard let row = table.indexPathForRow(at: point)?.row,
              suggestions.indices.contains(row)
        else {
            return
        }
        delegate?.searchViewDidAppend(suggestions[row])
    }
}

extension YT6SearchView: UITextFieldDelegate {
    /// `editingDidEndOnExit:` @74450: only a non-empty query is searched.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = query
        if !text.isEmpty {
            delegate?.searchViewDidSubmit(text)
        }
        return false
    }
}

extension YT6SearchView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        suggestions.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let dequeued = tableView.dequeueReusableCell(
            withIdentifier: YT6SearchSuggestionCell.reuseId, for: indexPath
        )
        guard let cell = dequeued as? YT6SearchSuggestionCell else {
            return dequeued
        }
        cell.configure(with: suggestions[indexPath.row])
        cell.appendButton.removeTarget(nil, action: nil, for: .allEvents)
        cell.appendButton.addTarget(self, action: #selector(appendPressed(_:)), for: .touchUpInside)
        return cell
    }

    /// `tableView:didSelectRowAtIndexPath:` @740a4 → `searchSuggestionDidPress:`
    /// @14994, which searches it right away.
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        delegate?.searchViewDidSubmit(suggestions[indexPath.row])
    }

    /// Opaline keeps its search history on disk; one entry can still be
    /// swiped away, which adds nothing to the 2.0.0 look.
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        delegate?.searchViewCanDelete(suggestions[indexPath.row]) ?? false
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, suggestions.indices.contains(indexPath.row) else {
            return
        }
        delegate?.searchViewDelete(suggestions[indexPath.row])
    }
}
