public enum TaskValidationError: Error, Sendable, Equatable {
    case emptyTitle
    case completedInFuture
}

