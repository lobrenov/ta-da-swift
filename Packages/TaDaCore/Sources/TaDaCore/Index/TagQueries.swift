import Foundation

/// A tag in the tag tree, with the number of files carrying it or any child of it, and its children by name.
public struct TagNode: Hashable, Sendable, Identifiable {
    public var tag: Tag
    public var count: Int
    public var children: [TagNode]

    public var id: String { tag.path }
}

/// What a tag's page lists, or Untagged's.
public struct TagBrowser: Hashable, Sendable {
    /// The areas by title, then the projects by title.
    public var areasAndProjects: [Item]
    /// Open tasks in Today's groups, with the tasks without a parent last.
    public var groups: [TaskGroup]
    /// Done and Cancelled tasks, by title.
    public var completed: [Item]
    /// Notes, by title.
    public var notes: [Item]
    /// The tag's children in the tag tree; none for Untagged.
    public var children: [TagNode]
}

/// The tag queries. A file is tagged by its own tags only, never its parent's.
extension VaultIndex {
    /// Every carried tag and its parents, as a tree. Each level is sorted by name, ignoring case. A parent carried by
    /// no file takes its spelling from a child.
    public func tagTree() -> [TagNode] {
        var tags: [String: Tag] = [:]
        var carriers: [String: Set<String>] = [:]
        for tag in carriedTags.sorted(by: { $0.path < $1.path }) {
            let paths = paths(carrying: tag.path)
            var node: Tag? = tag
            while let current = node {
                if tags[current.path] == nil { tags[current.path] = current }
                carriers[current.path, default: []].formUnion(paths)
                node = current.parent
            }
        }
        let byParent = Dictionary(grouping: tags.values) { $0.parent?.path ?? "" }
        func nodes(under parent: String) -> [TagNode] {
            (byParent[parent] ?? []).sorted(by: Self.byLeaf).map { tag in
                TagNode(tag: tag, count: carriers[tag.path]?.count ?? 0, children: nodes(under: tag.path))
            }
        }
        return nodes(under: "")
    }

    /// Items that carry the tag or any child of it, sorted by title.
    public func items(tagged tag: Tag) -> [Item] {
        carriedTags.filter { $0.path == tag.path || tag.isAncestor(of: $0) }
            .reduce(into: Set<String>()) { $0.formUnion(paths(carrying: $1.path)) }
            .compactMap { items[$0] }
            .sorted(by: Self.byTitle)
    }

    /// Areas, projects, tasks and notes that aren't logged and carry no tag, sorted by title.
    public func untagged() -> [Item] {
        liveItems.filter(\.tags.isEmpty).sorted(by: Self.byTitle)
    }

    /// The page for a tag, including its children's files, or for Untagged when `tag` is nil.
    public func tagBrowser(_ tag: Tag?) -> TagBrowser {
        let files = tag.map { items(tagged: $0) } ?? untagged()
        let tasks = files.filter { $0.properties.kind == .task }
        var groups = grouped(tasks.filter { !$0.properties.status.isClosed })
        if let loose = groups.firstIndex(where: { $0.parent == nil }) { groups.append(groups.remove(at: loose)) }
        return TagBrowser(
            areasAndProjects: files.filter { $0.properties.kind == .area } + files.filter { $0.properties.kind == .project },
            groups: groups,
            completed: tasks.filter(\.properties.status.isClosed),
            notes: files.filter { $0.properties.kind == .note },
            children: tag.flatMap { node(for: $0, in: tagTree()) }?.children ?? []
        )
    }

    /// Tags for autocomplete: those with a segment starting with the query, ignoring case. Tags whose first segment
    /// matches come first, then the most used, then by path. At most `limit`.
    public func tagSuggestions(_ query: String, limit: Int = 50) -> [TagNode] {
        let query = query.lowercased()
        var matches: [(node: TagNode, first: Bool)] = []
        func visit(_ nodes: [TagNode]) {
            for node in nodes {
                let segmentStarts = [node.tag.path.startIndex] + node.tag.path.indices.filter { node.tag.path[$0] == "/" }
                    .map { node.tag.path.index(after: $0) }
                if let start = segmentStarts.first(where: { node.tag.path[$0...].hasPrefix(query) }) {
                    matches.append((TagNode(tag: node.tag, count: node.count, children: []), start == node.tag.path.startIndex))
                }
                visit(node.children)
            }
        }
        visit(tagTree())
        return matches.sorted { a, b in
            if a.first != b.first { return a.first }
            if a.node.count != b.node.count { return a.node.count > b.node.count }
            return a.node.tag.path < b.node.tag.path
        }.prefix(limit).map(\.node)
    }

    private func node(for tag: Tag, in nodes: [TagNode]) -> TagNode? {
        for node in nodes {
            if node.tag.path == tag.path { return node }
            if node.tag.isAncestor(of: tag) { return self.node(for: tag, in: node.children) }
        }
        return nil
    }

    private static func byLeaf(_ a: Tag, _ b: Tag) -> Bool {
        let order = a.leaf.localizedStandardCompare(b.leaf)
        return order == .orderedSame ? a.path < b.path : order == .orderedAscending
    }
}
