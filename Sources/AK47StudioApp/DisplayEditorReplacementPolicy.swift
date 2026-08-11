enum DisplayEditorReplacementDecision: Equatable {
  case blocked
  case confirmDiscard
  case proceed
}

enum DisplayEditorReplacementPolicy {
  /// A newly mounted embedded editor reports its draft state on `onAppear`.
  /// Until that callback arrives, an existing input is treated conservatively
  /// as a draft that requires confirmation rather than as a clean editor.
  static func decision(
    hasEditorInput: Bool,
    draftState: DisplayAnimationEditorDraftState?,
    replacementInProgress: Bool
  ) -> DisplayEditorReplacementDecision {
    guard !replacementInProgress, draftState?.isBusy != true else {
      return .blocked
    }
    guard hasEditorInput else { return .proceed }
    guard let draftState else { return .confirmDiscard }
    return draftState.requiresReplacementConfirmation ? .confirmDiscard : .proceed
  }
}
