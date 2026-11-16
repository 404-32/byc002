///|
/// General topology classification used by the broader diagnostic pipeline.
pub struct TopologyAssessment {
  status : String
  node_count : Int32
  edge_count : Int32
  connected_components : Int32
  cycle_rank : Int32
  unknown_edge_ids : Array[String]
  isolated_node_ids : Array[String]
  warnings : Array[String]
}

///|
fn find_root(parents : Array[Int32], item : Int32) -> Int32 {
  let mut current = item
  while parents[current] != current {
    current = parents[current]
  }
  current
}

///|
/// Assess connectedness and cycle rank without requiring a radial tree.
pub fn assess_topology(
  network : Network,
  unknown_edge_ids? : Array[String],
) -> TopologyAssessment {
  let n = network.nodes.length()
  let unknown_edges = match unknown_edge_ids {
    Some(value) => value
    None => []
  }
  let warnings : Array[String] = []
  if n == 0 {
    warnings.push("topology contains no nodes")
    return {
      status: "empty",
      node_count: 0,
      edge_count: network.edges.length(),
      connected_components: 0,
      cycle_rank: 0,
      unknown_edge_ids: unknown_edges,
      isolated_node_ids: [],
      warnings,
    }
  }
  let parents : Array[Int32] = Array::make(n, 0)
  for index in 0..<n {
    parents[index] = index
  }
  let mut valid_edges = 0
  let degrees : Array[Int32] = Array::make(n, 0)
  for edge in network.edges {
    let from = network.find_node(edge.from_id)
    let to = network.find_node(edge.to_id)
    match (from, to) {
      (Some(left), Some(right)) => {
        valid_edges += 1
        degrees[left] += 1
        degrees[right] += 1
        let root_left = find_root(parents, left)
        let root_right = find_root(parents, right)
        if root_left != root_right {
          parents[root_right] = root_left
        }
      }
      _ => warnings.push("edge '" + edge.id + "' has an unknown endpoint")
    }
  }
  let component_marker : Array[Bool] = Array::make(n, false)
  let mut components = 0
  for index in 0..<n {
    let root = find_root(parents, index)
    if !component_marker[root] {
      component_marker[root] = true
      components += 1
    }
  }
  let raw_rank = valid_edges - n + components
  let cycle_rank = if raw_rank > 0 { raw_rank } else { 0 }
  let isolated : Array[String] = []
  for index in 0..<n {
    if degrees[index] == 0 && network.nodes[index].kind is Meter {
      isolated.push(network.nodes[index].id)
    }
  }
  let status = if unknown_edges.length() > 0 || isolated.length() > 0 {
    "partial"
  } else if components > 1 {
    "disconnected"
  } else if cycle_rank > 0 {
    "weakly_meshed"
  } else {
    "radial"
  }
  if components > 1 {
    warnings.push("network contains multiple connected components")
  }
  if cycle_rank > 0 {
    warnings.push(
      "network contains " + cycle_rank.to_string() + " independent cycle(s)",
    )
  }
  if unknown_edges.length() > 0 {
    warnings.push(
      "topology is partial; " +
      unknown_edges.length().to_string() +
      " relationship(s) are unregistered",
    )
  }
  if isolated.length() > 0 {
    warnings.push(
      "topology is partial; " +
      isolated.length().to_string() +
      " meter node(s) have no registered edge",
    )
  }
  {
    status,
    node_count: n,
    edge_count: valid_edges,
    connected_components: components,
    cycle_rank,
    unknown_edge_ids: unknown_edges,
    isolated_node_ids: isolated,
    warnings,
  }
}
