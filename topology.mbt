///|
pub enum TopologyError {
  EmptyNetwork
  RootNotFound(String)
  DuplicateNodeId(String)
  DuplicateEdgeId(String)
  UnknownEndpoint(String)
  NotRadial
  Disconnected(String)
}

///|
pub fn TopologyError::describe(self : TopologyError) -> String {
  match self {
    EmptyNetwork => "network has no nodes"
    RootNotFound(id) => "root node '" + id + "' was not found"
    DuplicateNodeId(id) => "duplicate node id '" + id + "'"
    DuplicateEdgeId(id) => "duplicate edge id '" + id + "'"
    UnknownEndpoint(id) => "edge references unknown node '" + id + "'"
    NotRadial => "edge count must equal node count - 1"
    Disconnected(id) => "node '" + id + "' is unreachable from the root"
  }
}

///|
pub struct Tree {
  root : Int32
  order : Array[Int32]
  parent : Array[Int32]
  parent_edge : Array[Int32]
  children : Array[Array[Int32]]
}

///|
pub fn Tree::root(self : Tree) -> Int32 {
  self.root
}

///|
pub fn Tree::parent(self : Tree, node : Int32) -> Int32 {
  self.parent[node]
}

///|
pub fn Tree::node_count(self : Tree) -> Int32 {
  self.parent.length()
}

///|
fn fail_topology(error : TopologyError) -> Result[Tree, TopologyError] {
  Err(error)
}

///|
/// Validate a radial network and orient it away from its source root.
pub fn build_tree(network : Network) -> Result[Tree, TopologyError] {
  let n = network.nodes.length()
  if n == 0 {
    return fail_topology(EmptyNetwork)
  }
  // Node identifiers must be unique.
  let mut i = 0
  while i < n {
    let mut j = i + 1
    while j < n {
      if network.nodes[i].id == network.nodes[j].id {
        return fail_topology(DuplicateNodeId(network.nodes[i].id))
      }
      j += 1
    }
    i += 1
  }
  let root = match network.find_node(network.root_id) {
    Some(index) => index
    None => return fail_topology(RootNotFound(network.root_id))
  }
  let edge_count = network.edges.length()
  if edge_count != n - 1 {
    return fail_topology(NotRadial)
  }
  let adjacency : Array[Array[(Int32, Int32)]] = []
  let seen_edge_ids : Map[String, Bool] = Map([])
  for _ in 0..<n {
    adjacency.push([])
  }
  let mut e = 0
  while e < edge_count {
    let edge = network.edges[e]
    if seen_edge_ids.contains(edge.id) {
      return fail_topology(DuplicateEdgeId(edge.id))
    }
    seen_edge_ids.set(edge.id, true)
    let from = match network.find_node(edge.from_id) {
      Some(index) => index
      None => return fail_topology(UnknownEndpoint(edge.from_id))
    }
    let to = match network.find_node(edge.to_id) {
      Some(index) => index
      None => return fail_topology(UnknownEndpoint(edge.to_id))
    }
    adjacency[from].push((to, e))
    adjacency[to].push((from, e))
    e += 1
  }
  let parent : Array[Int32] = Array::make(n, -1)
  let parent_edge : Array[Int32] = Array::make(n, -1)
  let children : Array[Array[Int32]] = []
  for _ in 0..<n {
    children.push([])
  }
  let visited : Array[Bool] = Array::make(n, false)
  let order : Array[Int32] = []
  let queue : Array[Int32] = [root]
  visited[root] = true
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head += 1
    order.push(u)
    for item in adjacency[u] {
      let (v, edge_index) = item
      if !visited[v] {
        visited[v] = true
        parent[v] = u
        parent_edge[v] = edge_index
        children[u].push(v)
        queue.push(v)
      }
    }
  }
  let mut missing = -1
  for index in 0..<n {
    if !visited[index] {
      missing = index
      break
    }
  }
  if missing >= 0 {
    return fail_topology(Disconnected(network.nodes[missing].id))
  }
  Ok({ root, order, parent, parent_edge, children, })
}

///|
/// Mark the supplied node and every node below it in the rooted tree.
pub fn downstream_mask(tree : Tree, node : Int32) -> Array[Bool] {
  let mask : Array[Bool] = Array::make(tree.node_count(), false)
  if node < 0 || node >= tree.node_count() {
    return mask
  }
  let stack : Array[Int32] = [node]
  while stack.length() > 0 {
    let current = match stack.pop() {
      Some(value) => value
      None => break
    }
    mask[current] = true
    for child in tree.children[current] {
      stack.push(child)
    }
  }
  mask
}

///|
pub fn downstream_meter_ids(
  network : Network,
  tree : Tree,
  node : Int32,
) -> Array[String] {
  let mask = downstream_mask(tree, node)
  let out : Array[String] = []
  for index in 0..<network.nodes.length() {
    if mask[index] && network.nodes[index].kind is Meter {
      out.push(network.nodes[index].id)
    }
  }
  out
}

///|
pub fn all_meter_ids(network : Network) -> Array[String] {
  let out : Array[String] = []
  for node in network.nodes {
    if node.kind is Meter {
      out.push(node.id)
    }
  }
  out
}

///|
pub fn fault_node_for_edge(
  network : Network,
  tree : Tree,
  edge_id : String,
) -> Int32? {
  let mut edge_index = -1
  for index in 0..<network.edges.length() {
    if network.edges[index].id == edge_id {
      edge_index = index
      break
    }
  }
  if edge_index < 0 {
    return None
  }
  for node in 0..<tree.node_count() {
    if tree.parent_edge[node] == edge_index {
      return Some(node)
    }
  }
  None
}
