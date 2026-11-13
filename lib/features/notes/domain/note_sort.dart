enum NoteSortField {
  modified,
  created,
  title,
}

enum NoteSortOrder {
  ascending,
  descending,
}

class NoteSortOption {
  final NoteSortField field;
  final NoteSortOrder order;

  const NoteSortOption({
    this.field = NoteSortField.modified,
    this.order = NoteSortOrder.descending,
  });

  String get sqlOrderBy {
    final direction = order == NoteSortOrder.ascending ? 'ASC' : 'DESC';
    switch (field) {
      case NoteSortField.modified:
        return 'is_pinned DESC, updated_at $direction';
      case NoteSortField.created:
        return 'is_pinned DESC, created_at $direction';
      case NoteSortField.title:
        return 'is_pinned DESC, title COLLATE NOCASE $direction, updated_at DESC';
    }
  }

  String get label {
    final orderLabel = order == NoteSortOrder.ascending ? 'Ascending' : 'Descending';
    switch (field) {
      case NoteSortField.modified:
        return 'Modified date ($orderLabel)';
      case NoteSortField.created:
        return 'Created date ($orderLabel)';
      case NoteSortField.title:
        return 'Title ($orderLabel)';
    }
  }

  NoteSortOption copyWith({
    NoteSortField? field,
    NoteSortOrder? order,
  }) {
    return NoteSortOption(
      field: field ?? this.field,
      order: order ?? this.order,
    );
  }
}
