const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// A graph represented as an adjacency list
pub const Graph = struct {
    alloc: *Allocator,
    vertices: ArrayList(Vertex),
    edges: ArrayList(Edge),

    pub const Vertex = struct {
        /// Indexes for each of the edges that connect to the vertex.
        edges: ArrayList(usize),
        explored: bool = false,

        fn deinit(graph: Vertex) void {
            graph.edges.deinit();
        }
    };

    // The two vertices that the Edge connects.
    // In a directed graph, goes from 0 to 1;
    pub const Edge = struct {
        v0: usize,
        v1: usize,
    };

    pub fn init(alloc: *Allocator) Graph {
        return .{
            .alloc = alloc,
            .vertices = ArrayList(Vertex).init(alloc),
            .edges = ArrayList(Edge).init(alloc),
        };
    }

    pub fn deinit(graph: Graph) void {
        for (graph.vertices.items) |vertex| {
            vertex.deinit();
        }
        graph.vertices.deinit();
        graph.edges.deinit();
    }

    // Reset explored state in graph.
    pub fn reset(graph: *Graph) void {
        for (graph.vertices.items) |vertex| {
            vertex.explored = false;
        }
    }

    /// breadth-first search, marks reachable vertices given starting vertex s.
    fn bfs(graph: *Graph, s: usize) !void {
        // queue of vertices, to track state while searching
        var q = ArrayList(usize).init(graph.alloc);
        defer q.deinit();

        graph.vertices.items[s].explored = true;
        try q.append(s);

        while (q.items.len != 0) {
            // For bfs, it's a queue so FIFO
            const v = q.orderedRemove(0);
            for (graph.vertices.items[v].edges.items) |e| {
                const edge = graph.edges.items[e];
                // In directed, w must be v1.
                // In undirected, w can be v0 or v1.
                // Undirected for now.
                var w = if (v == edge.v1) edge.v0 else edge.v1;
                if (!graph.vertices.items[w].explored) {
                    try q.append(w);
                }
                graph.vertices.items[w].explored = true;
            }
        }
    }
};

test "bfs" {
    var alloc = testing.allocator;

    var graph = Graph.init(alloc);
    defer graph.deinit();

    try graph.vertices.appendSlice(&[_]Graph.Vertex{
        .{ .edges = ArrayList(usize).init(alloc) },
        .{ .edges = ArrayList(usize).init(alloc) },
        .{ .edges = ArrayList(usize).init(alloc) },
        .{ .edges = ArrayList(usize).init(alloc) },
        .{ .edges = ArrayList(usize).init(alloc) },
        .{ .edges = ArrayList(usize).init(alloc) },
    });
    try graph.vertices.items[0].edges.appendSlice(&[_]usize{ 0, 1 });
    try graph.vertices.items[1].edges.appendSlice(&[_]usize{ 0, 3 });
    try graph.vertices.items[2].edges.appendSlice(&[_]usize{ 1, 3, 4 });
    try graph.vertices.items[3].edges.appendSlice(&[_]usize{ 2, 3, 5, 6 });
    try graph.vertices.items[4].edges.appendSlice(&[_]usize{ 4, 5, 7 });
    try graph.vertices.items[5].edges.appendSlice(&[_]usize{ 6, 7 });

    try graph.edges.appendSlice(&[_]Graph.Edge{
        .{ .v0 = 0, .v1 = 1 },
        .{ .v0 = 0, .v1 = 2 },
        .{ .v0 = 1, .v1 = 3 },
        .{ .v0 = 2, .v1 = 3 },
        .{ .v0 = 2, .v1 = 4 },
        .{ .v0 = 3, .v1 = 4 },
        .{ .v0 = 3, .v1 = 5 },
        .{ .v0 = 4, .v1 = 5 },
    });

    try graph.bfs(0);

    for (graph.vertices.items) |vertex, i| {
        std.debug.print("{d}", .{i});
        try testing.expectEqual(true, vertex.explored);
    }
}
