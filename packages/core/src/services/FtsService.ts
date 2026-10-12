export class FtsService {
  /**
   * Sanitizes user search input into FTS5 query with prefix matching.
   * Strips dangerous FTS operators and formats tokens into prefix terms.
   */
  public static sanitizeQuery(query: string): string {
    const trimmed = query.trim();
    if (!trimmed) {
      return '';
    }

    // Split on whitespace and remove special characters
    const tokens = trimmed
      .replace(/[^\p{L}\p{N}\s]/gu, ' ')
      .split(/\s+/)
      .map(t => t.trim())
      .filter(t => t.length > 0);

    if (tokens.length === 0) {
      return '';
    }

    // Append wildcard * for prefix searching
    return tokens.map(t => `"${t}"*`).join(' ');
  }

  /**
   * Extracts plain text from an array of NoteBlocks for FTS indexing.
   */
  public static extractPlainText(blocks: Array<{ text: string }>): string {
    return blocks.map(b => b.text).join('\n');
  }
}
