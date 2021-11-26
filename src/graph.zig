const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

/// Map from vertex index to label
const LabelMap = std.AutoHashMap(usize, []const u8);

/// A graph represented as an adjacency list
pub const Graph = struct {
    alloc: *Allocator,
    vertices: ArrayList(Vertex),
    edges: ArrayList(Edge),
    /// Map of vertex label to index in .vertices.
    label_to_vertex: StringHashMap(VertexIdx),

    pub const VertexIdx = usize;
    pub const EdgeIdx = usize;

    pub const Vertex = struct {
        /// Indexes for each of the edges that connect to the vertex.
        edges: ArrayList(EdgeIdx),
        explored: bool,

        fn init(alloc: *Allocator) Vertex {
            return .{
                .edges = ArrayList(EdgeIdx).init(alloc),
                .explored = false,
            };
        }

        fn deinit(graph: Vertex) void {
            graph.edges.deinit();
        }
    };

    // The two vertices that the Edge connects.
    // In a directed graph, goes from 0 to 1;
    pub const Edge = struct {
        v0: VertexIdx,
        v1: VertexIdx,
    };

    // prefer GraphBuilder
    pub fn init(alloc: *Allocator) Graph {
        return .{
            .alloc = alloc,
            .vertices = ArrayList(Vertex).init(alloc),
            .edges = ArrayList(Edge).init(alloc),
            .label_to_vertex = StringHashMap(VertexIdx).init(alloc),
        };
    }

    pub fn deinit(graph: *Graph) void {
        for (graph.vertices.items) |vertex| {
            vertex.deinit();
        }
        graph.vertices.deinit();
        graph.edges.deinit();
        graph.label_to_vertex.deinit();
    }

    // Reset explored state in graph.
    pub fn reset(graph: *Graph) void {
        for (graph.vertices.items) |vertex| {
            vertex.explored = false;
        }
    }

    pub fn add_vertices(graph: *Graph, v_labels: [][]const u8) !void {
        for (v_labels) |v_label, i| {
            // Only add if not already added, otherwise skip to next
            graph.label_to_vertex.putNoClobber(v_label, i) catch continue;
            try graph.vertices.append(Graph.Vertex.init(graph.alloc));
        }
    }

    pub fn add_edges(graph: *Graph, e_labels: []Tuple) !void {
        // For each tuple, create edge
        // Then for each vertex in tuple, update with edge
        //
        // Lookup of vertex cannot fail if the vertices builder was correct.
        for (e_labels) |e_tuple, e_idx| {
            const v0 = graph.label_to_vertex.get(e_tuple.v0) orelse return error.vertex_not_found;
            const v1 = graph.label_to_vertex.get(e_tuple.v1) orelse return error.vertex_not_found;
            try graph.edges.append(.{
                .v0 = v0,
                .v1 = v1,
            });

            try graph.vertices.items[v0].edges.append(e_idx);
            try graph.vertices.items[v1].edges.append(e_idx);
        }
    }

    fn vertex_to_label(graph: Graph) !LabelMap {
        var res = LabelMap.init(graph.alloc);
        var it = graph.label_to_vertex.iterator();
        while (it.next()) |kv| {
            try res.put(kv.value_ptr.*, kv.key_ptr.*);
        }
        return res;
    }

    /// breadth-first search, marks reachable vertices given starting vertex s.
    fn bfs(graph: *Graph, s: VertexIdx) !void {
        // queue of vertices, to track state while searching
        var q = ArrayList(VertexIdx).init(graph.alloc);
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

    var vertices = [_][]const u8{ "s", "a", "b", "c", "d", "e" };
    var edges = [_]Tuple{
        .{ .v0 = "s", .v1 = "a" },
        .{ .v0 = "s", .v1 = "b" },
        .{ .v0 = "a", .v1 = "c" },
        .{ .v0 = "b", .v1 = "c" },
        .{ .v0 = "b", .v1 = "d" },
        .{ .v0 = "c", .v1 = "d" },
        .{ .v0 = "c", .v1 = "e" },
        .{ .v0 = "d", .v1 = "e" },
    };

    var graph = Graph.init(alloc);
    try graph.add_vertices(vertices[0..]);
    try graph.add_edges(edges[0..]);
    defer graph.deinit();

    try graph.bfs(0);

    for (graph.vertices.items) |vertex| {
        try testing.expectEqual(true, vertex.explored);
    }
}

// For building edges from labels
const Tuple = struct {
    v0: []const u8,
    v1: []const u8,
};

test "build graph" {
    var alloc = testing.allocator;
    var vertices = [_][]const u8{ "s", "a", "b", "c", "d", "e" };
    var edges = [_]Tuple{
        .{ .v0 = "s", .v1 = "a" },
        .{ .v0 = "s", .v1 = "b" },
        .{ .v0 = "a", .v1 = "c" },
        .{ .v0 = "b", .v1 = "c" },
        .{ .v0 = "b", .v1 = "d" },
        .{ .v0 = "c", .v1 = "d" },
        .{ .v0 = "c", .v1 = "e" },
        .{ .v0 = "d", .v1 = "e" },
    };

    var graph = Graph.init(alloc);
    try graph.add_vertices(vertices[0..]);
    try graph.add_edges(edges[0..]);
    defer graph.deinit();

    // manually build expected
    var expected_graph = Graph.init(alloc);
    defer expected_graph.deinit();
    try expected_graph.vertices.appendSlice(&[_]Graph.Vertex{
        Graph.Vertex.init(alloc),
        Graph.Vertex.init(alloc),
        Graph.Vertex.init(alloc),
        Graph.Vertex.init(alloc),
        Graph.Vertex.init(alloc),
        Graph.Vertex.init(alloc),
    });
    try expected_graph.vertices.items[0].edges.appendSlice(&[_]usize{ 0, 1 });
    try expected_graph.vertices.items[1].edges.appendSlice(&[_]usize{ 0, 2 });
    try expected_graph.vertices.items[2].edges.appendSlice(&[_]usize{ 1, 3, 4 });
    try expected_graph.vertices.items[3].edges.appendSlice(&[_]usize{ 2, 3, 5, 6 });
    try expected_graph.vertices.items[4].edges.appendSlice(&[_]usize{ 4, 5, 7 });
    try expected_graph.vertices.items[5].edges.appendSlice(&[_]usize{ 6, 7 });

    try expected_graph.edges.appendSlice(&[_]Graph.Edge{
        .{ .v0 = 0, .v1 = 1 }, //s,a
        .{ .v0 = 0, .v1 = 2 }, //s,b
        .{ .v0 = 1, .v1 = 3 }, //a,c
        .{ .v0 = 2, .v1 = 3 }, //b,c
        .{ .v0 = 2, .v1 = 4 }, //b,d
        .{ .v0 = 3, .v1 = 4 }, //c,d
        .{ .v0 = 3, .v1 = 5 }, //c,e
        .{ .v0 = 4, .v1 = 5 }, //d,e
    });

    try expected_graph.label_to_vertex.put("s", 0);
    try expected_graph.label_to_vertex.put("a", 1);
    try expected_graph.label_to_vertex.put("b", 2);
    try expected_graph.label_to_vertex.put("c", 3);
    try expected_graph.label_to_vertex.put("d", 4);
    try expected_graph.label_to_vertex.put("e", 5);

    // Assert equals
    for (expected_graph.vertices.items) |expected_vertex, i| {
        try testing.expectEqualSlices(Graph.EdgeIdx, expected_vertex.edges.items, graph.vertices.items[i].edges.items);
    }

    // TODO check adding a vertex that already exists
    // (not implemeted) check adding an edge that already exists
}
