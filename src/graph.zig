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
            var entry = try graph.label_to_vertex.getOrPut(v_label);
            if (entry.found_existing) {
                continue;
            } else {
                entry.value_ptr.* = i;
            }
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
                    graph.vertices.items[w].explored = true;
                }
            }
        }
    }

    pub const ShortestPath = StringHashMap(usize);

    /// Shortest path from s to each vertex.
    fn shortest_path(graph: *Graph, s: VertexIdx) !ShortestPath {
        var vtl = try graph.vertex_to_label();
        defer vtl.deinit();

        var res = ShortestPath.init(graph.alloc);
        for (graph.vertices.items) |_, v_idx| {
            try res.put(vtl.get(v_idx).?, undefined);
        }
        try res.put(vtl.get(s).?, 0);

        // bfs uses queue to track state
        var q = ArrayList(VertexIdx).init(graph.alloc);
        defer q.deinit();

        graph.vertices.items[s].explored = true;
        try q.append(s);
        while (q.items.len != 0) {
            const v_idx = q.orderedRemove(0);
            const v = graph.vertices.items[v_idx];
            for (v.edges.items) |e_idx| {
                const e = graph.edges.items[e_idx];
                const w = if (e.v0 == v_idx) e.v1 else e.v0;
                if (!graph.vertices.items[w].explored) {
                    try q.append(w);
                    graph.vertices.items[w].explored = true;
                    try res.put(vtl.get(w).?, res.get(vtl.get(v_idx).?).? + 1);
                }
            }
        }

        return res;
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

test "shortest_path" {
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

    var shortest = try graph.shortest_path(0);
    defer shortest.deinit();

    try testing.expectEqual(shortest.get("s"), 0);
    try testing.expectEqual(shortest.get("a"), 1);
    try testing.expectEqual(shortest.get("b"), 1);
    try testing.expectEqual(shortest.get("c"), 2);
    try testing.expectEqual(shortest.get("d"), 2);
    try testing.expectEqual(shortest.get("e"), 3);
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
    // Vertices
    try testing.expectEqual(expected_graph.vertices.items.len, graph.vertices.items.len);
    for (expected_graph.vertices.items) |expected_vertex, i| {
        const v = graph.vertices.items[i];
        try testing.expectEqual(false, v.explored);
        try testing.expectEqualSlices(Graph.EdgeIdx, expected_vertex.edges.items, v.edges.items);
    }
    // Edges
    try testing.expectEqual(expected_graph.edges.items.len, graph.edges.items.len);
    for (expected_graph.edges.items) |expected_edge, i| {
        const e = graph.edges.items[i];
        try testing.expectEqual(expected_edge, e);
    }
    // label_to_vertex
    try testing.expectEqual(expected_graph.label_to_vertex.count(), graph.label_to_vertex.count());
    var it = expected_graph.label_to_vertex.iterator();
    while (it.next()) |expected_kv| {
        if (graph.label_to_vertex.get(expected_kv.key_ptr.*)) |v_idx| {
            try testing.expectEqual(expected_kv.value_ptr.*, v_idx);
        } else {
            return error.expectedKeyNotFound;
        }
    }

    // TODO check adding a vertex that already exists
    var duplicate_vertex = [_][]const u8{"e"};
    try graph.add_vertices(duplicate_vertex[0..]);

    try testing.expectEqual(expected_graph.label_to_vertex.count(), graph.label_to_vertex.count());
    var it_dup = expected_graph.label_to_vertex.iterator();
    while (it_dup.next()) |expected_kv| {
        if (graph.label_to_vertex.get(expected_kv.key_ptr.*)) |v_idx| {
            try testing.expectEqual(expected_kv.value_ptr.*, v_idx);
        } else {
            return error.expectedKeyNotFound;
        }
    }

    // (not implemeted) check adding an edge that already exists
}
