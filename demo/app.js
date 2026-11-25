(() => {
  const scenarios = window.GRIDDIAGNOSE_SCENARIOS || [];
  const state = {
    scenario: null,
    selectedCandidate: 0,
    positions: new Map(),
    orientedChildren: new Map(),
    faultNode: null,
  };

  const COLORS = {
    energized: "#44dfa3",
    outage: "#ff6178",
    unknown: "#8192a1",
    junction: "#5b83b4",
    source: "#5ed8ff",
    fault: "#ffbf5b",
  };

  const $ = (selector) => document.querySelector(selector);
  const escapeXml = (value) =>
    String(value).replace(/[<>&'"]/g, (char) => ({
      "<": "&lt;", ">": "&gt;", "&": "&amp;", "'": "&apos;", '"': "&quot;",
    }[char]));

  function latestObservations(observations) {
    const latest = new Map();
    for (const observation of observations) {
      const previous = latest.get(observation.node_id);
      if (!previous || observation.observed_at >= previous.observed_at) {
        latest.set(observation.node_id, observation);
      }
    }
    return latest;
  }

  function orientNetwork(network) {
    const adjacency = new Map(network.nodes.map((node) => [node.id, []]));
    for (const edge of network.edges) {
      adjacency.get(edge.from).push([edge.to, edge.id]);
      adjacency.get(edge.to).push([edge.from, edge.id]);
    }
    const parent = new Map();
    const children = new Map(network.nodes.map((node) => [node.id, []]));
    const depth = new Map([[network.root, 0]]);
    const queue = [network.root];
    while (queue.length) {
      const current = queue.shift();
      for (const [neighbor, edgeId] of adjacency.get(current)) {
        if (depth.has(neighbor)) continue;
        depth.set(neighbor, depth.get(current) + 1);
        parent.set(neighbor, { parent: current, edgeId });
        children.get(current).push(neighbor);
        queue.push(neighbor);
      }
    }
    return { parent, children, depth };
  }

  function layout(network, children, depth) {
    const positions = new Map();
    const maxDepth = Math.max(...depth.values());
    let leafIndex = 0;
    const leafCount = network.nodes.filter((node) => !(children.get(node.id) || []).length).length;
    const width = 960;
    const left = 80;
    const step = leafCount > 1 ? width / (leafCount - 1) : 0;
    const visit = (nodeId) => {
      const kids = children.get(nodeId) || [];
      const d = depth.get(nodeId) || 0;
      const y = 70 + (maxDepth ? d * (460 / maxDepth) : 200);
      if (!kids.length) {
        const x = leafCount === 1 ? 560 : left + leafIndex * step;
        leafIndex += 1;
        positions.set(nodeId, { x, y });
        return x;
      }
      const xs = kids.map(visit);
      const x = xs.reduce((sum, value) => sum + value, 0) / xs.length;
      positions.set(nodeId, { x, y });
      return x;
    };
    visit(network.root);
    return positions;
  }

  function candidateState() {
    if (state.scenario.kind === "analysis" && state.scenario.analysis) {
      return state.scenario.analysis.candidates[state.selectedCandidate] || null;
    }
    return null;
  }

  function renderedNetwork() {
    const { network, observations } = state.scenario;
    const latest = latestObservations(observations);
    const oriented = orientNetwork(network);
    state.positions = layout(network, oriented.children, oriented.depth);
    state.orientedChildren = oriented.children;
    const candidate = candidateState();
    const affected = new Set(candidate?.affected_meter_ids || []);
    state.faultNode = candidate?.fault_node_id || null;

    const edges = network.edges.map((edge) => {
      const a = state.positions.get(edge.from);
      const b = state.positions.get(edge.to);
      if (!a || !b) return "";
      const sourceSide = oriented.depth.get(edge.from) < oriented.depth.get(edge.to) ? edge.from : edge.to;
      const targetSide = sourceSide === edge.from ? edge.to : edge.from;
      const downstream = new Set();
      const stack = [targetSide];
      while (stack.length) {
        const node = stack.pop();
        if (downstream.has(node)) continue;
        downstream.add(node);
        stack.push(...(oriented.children.get(node) || []));
      }
      let className = "edge";
      if ([...downstream].some((node) => affected.has(node))) className += " affected";
      if (targetSide === state.faultNode) className += " fault";
      return `<line class="${className}" x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" />`;
    }).join("");

    const nodes = network.nodes.map((node) => {
      const position = state.positions.get(node.id);
      const observation = latest.get(node.id);
      let color = COLORS.source;
      let subtitle = "SOURCE";
      if (node.kind === "junction") {
        color = observation?.state === "outage" ? COLORS.outage : COLORS.junction;
        subtitle = "JUNCTION";
      } else if (node.kind === "meter") {
        color = COLORS[observation?.state || "unknown"];
        subtitle = observation?.state?.toUpperCase() || "NO DATA";
      }
      const radius = node.kind === "source" ? 20 : node.kind === "junction" ? 15 : 11;
      const affectedRing = affected.has(node.id)
        ? `<circle cx="${position.x}" cy="${position.y}" r="${radius + 7}" fill="none" stroke="${COLORS.fault}" stroke-opacity=".7" stroke-width="2" />`
        : "";
      const halo = node.kind === "source"
        ? `<circle class="source-halo" cx="${position.x}" cy="${position.y}" r="34" />`
        : "";
      return `
        <g class="node" data-node-id="${escapeXml(node.id)}">
          ${halo}
          ${affectedRing}
          <circle cx="${position.x}" cy="${position.y}" r="${radius}" fill="${color}1f" stroke="${color}" stroke-width="2" />
          <circle cx="${position.x}" cy="${position.y}" r="${Math.max(3, radius / 3)}" fill="${color}" />
          <text class="node-label" x="${position.x}" y="${position.y + radius + 15}">${escapeXml(node.label)}</text>
          <text class="node-sub" x="${position.x}" y="${position.y + radius + 27}">${escapeXml(subtitle)}</text>
        </g>`;
    }).join("");

    return edges + nodes;
  }

  function renderMap() {
    $("#scenario-eyebrow").textContent = state.scenario.eyebrow;
    $("#scenario-name").textContent = state.scenario.name;
    $("#scenario-description").textContent = state.scenario.description;
    $("#observation-count").textContent = `${state.scenario.observations.length} observations · ${state.scenario.network.nodes.length} nodes`;
    $("#network-map").innerHTML = renderedNetwork();
  }

  function rankingHtml() {
    if (state.scenario.kind === "restore") {
      const report = state.scenario.restoration;
      const statusText = report.status === "complete" ? "复电完成" : report.status === "partial" ? "部分恢复" : report.status === "unexpected_outage" ? "异常掉电" : "证据不足";
      return `
        <div class="restore-status">
          <strong>${statusText}</strong>
          <span>系统将“已确认恢复”“仍未恢复”和“暂无回传”分开处理，避免把通信缺失当成成功或失败。</span>
        </div>
        <div class="metrics">
          <div class="metric"><b>${report.restored_meter_ids.length}</b><span>已恢复</span></div>
          <div class="metric"><b>${report.unknown_meter_ids.length}</b><span>待核验</span></div>
          <div class="metric"><b>${report.still_out_meter_ids.length}</b><span>仍停电</span></div>
          <div class="metric"><b>${report.unexpected_outage_node_ids.length}</b><span>范围外异常</span></div>
        </div>`;
    }
    const candidates = state.scenario.analysis.candidates.slice(0, 5);
    return `<div class="ranking">${candidates.map((candidate, index) => `
      <button class="rank-row ${index === state.selectedCandidate ? "selected" : ""}" data-candidate="${index}" type="button">
        <div class="rank-top">
          <span class="rank-name">${index + 1}. ${escapeXml(candidate.section)}</span>
          <span class="rank-pct">${(candidate.confidence * 100).toFixed(1)}%</span>
        </div>
        <div class="rank-track"><div class="rank-fill" style="width:${Math.max(2, candidate.confidence * 100).toFixed(2)}%"></div></div>
      </button>`).join("")}</div>`;
  }

  function renderInspector() {
    if (state.scenario.kind === "combined") {
      const diagnostic = state.scenario.diagnostic;
      const outages = diagnostic.outage?.faults || [];
      const issues = [];
      if (diagnostic.topology) {
        issues.push({
          severity: diagnostic.topology.status === "radial" ? "ok" : "warning",
          title: `拓扑状态：${diagnostic.topology.status}`,
          detail: `${diagnostic.topology.connected_components} 个连通分量，${diagnostic.topology.cycle_rank} 个独立环路`,
        });
      }
      for (const fault of outages) {
        issues.push({
          severity: "critical",
          title: `故障假设 ${fault.candidate.edge_id} · ${fault.candidate.section}`,
          detail: `影响 ${fault.candidate.affected_meter_ids.length} 户，阶段置信度 ${(fault.candidate.confidence * 100).toFixed(1)}%`,
        });
      }
      for (const finding of diagnostic.phase.findings) {
        issues.push({
          severity: finding.severity,
          title: `三相诊断 · ${finding.node_id} · ${finding.kind}`,
          detail: finding.summary,
        });
      }
      for (const event of diagnostic.power_quality.events) {
        issues.push({
          severity: event.severity,
          title: `电能质量 · ${event.node_id} · ${event.kind}`,
          detail: `持续 ${event.duration_sec.toFixed(3)} s，偏离 ${event.deviation_percent.toFixed(1)}%`,
        });
      }
      for (const finding of diagnostic.telemetry.findings) {
        issues.push({
          severity: finding.severity,
          title: `可信度诊断 · ${finding.node_id} · ${finding.kind}`,
          detail: finding.summary,
        });
      }
      const primaryLabels = {
        supply_fault: "供电故障为主因",
        measurement_issue: "量测失真为主因",
        topology_issue: "拓扑登记问题为主因",
        mixed: "供电、量测与拓扑问题并存",
        no_incident: "未发现明确异常",
      };
      const causeLabels = {
        supply_fault: "供电故障",
        measurement_issue: "量测问题",
        topology_issue: "拓扑问题",
      };
      const caveats = [
        ...diagnostic.arbitration.undetermined_reasons,
        ...diagnostic.arbitration.conflicts,
      ];
      $("#result-panel").innerHTML = `
        <div class="result-hero">
          <div class="result-kicker">CAUSAL ARBITRATION</div>
          <h2>${primaryLabels[diagnostic.arbitration.primary_class] || diagnostic.arbitration.primary_class}</h2>
          <div class="result-section">跨模型核对设备、分支、时间窗和可信度后再确定主因</div>
          <div class="metrics">
            <div class="metric"><b>${outages.length}</b><span>故障假设</span></div>
            <div class="metric"><b>${diagnostic.phase.findings.length}</b><span>三相异常</span></div>
            <div class="metric"><b>${diagnostic.power_quality.events.length}</b><span>电压事件</span></div>
            <div class="metric"><b>${diagnostic.telemetry.findings.length}</b><span>可信度异常</span></div>
          </div>
          <div class="restore-status">
            <strong>综合置信度 ${(diagnostic.arbitration.overall_confidence * 100).toFixed(0)}%</strong>
            <span>${caveats.length ? escapeXml(caveats.join("；")) : "当前未发现跨模型证据冲突。"}</span>
          </div>
        </div>
        <div class="panel-title">根因分类</div>
        <div class="finding-list">${diagnostic.arbitration.causes.map((cause) => `
          <div class="finding ${cause.class === "supply_fault" ? "critical" : "warning"}">
            <i></i>
            <div><strong>${causeLabels[cause.class] || cause.class} · ${(cause.confidence * 100).toFixed(0)}%</strong><span>${escapeXml(cause.subject_ids.join(", "))}</span></div>
          </div>`).join("")}</div>
        <div class="panel-title">模型证据</div>
        <div class="finding-list">${issues.map((issue) => `
          <div class="finding ${issue.severity}">
            <i></i>
            <div><strong>${escapeXml(issue.title)}</strong><span>${escapeXml(issue.detail)}</span></div>
          </div>`).join("")}</div>`;
    } else if (state.scenario.kind === "analysis") {
      const candidate = candidateState();
      const analysis = state.scenario.analysis;
      const confidence = Math.max(0, Math.min(100, candidate.confidence * 100));
      $("#result-panel").innerHTML = `
        <div class="result-hero">
          <div class="result-kicker">TOP FAULT CANDIDATE</div>
          <h2>${escapeXml(candidate.section)}</h2>
          <div class="result-section">${escapeXml(candidate.edge_id)} · 故障节点 ${escapeXml(candidate.fault_node_id)}</div>
          <div class="confidence-row">
            <div class="confidence-ring" style="--confidence:${confidence}%"><span class="confidence-value">${confidence.toFixed(1)}%</span></div>
            <div class="confidence-copy">
              <strong>拓扑一致证据最高</strong>
              <span>使用 ${analysis.used_observation_count} 条最新观测，排序概率已归一化。</span>
            </div>
          </div>
          <div class="metrics">
            <div class="metric"><b>${candidate.affected_meter_ids.length}</b><span>受影响电表</span></div>
            <div class="metric"><b>${candidate.contradicting_node_ids.length}</b><span>矛盾证据</span></div>
            <div class="metric"><b>${candidate.blind_node_ids.length}</b><span>通信盲区</span></div>
            <div class="metric"><b>${analysis.candidates.length}</b><span>候选故障段</span></div>
          </div>
        </div>
        <div class="panel-title">候选排序</div>
        ${rankingHtml()}`;
    } else {
      $("#result-panel").innerHTML = `
        <div class="result-hero">
          <div class="result-kicker">RESTORATION VERIFICATION</div>
          <h2>${escapeXml(state.scenario.restoration.fault_edge_id)} 抢修核验</h2>
          <div class="result-section">按故障影响集合逐户核对复电状态</div>
        </div>
        ${rankingHtml()}`;
    }
    renderEvidence();
  }

  function renderEvidence() {
    const observations = [...state.scenario.observations]
      .sort((a, b) => b.observed_at - a.observed_at)
      .slice(0, 30);
    const labels = new Map(state.scenario.network.nodes.map((node) => [node.id, node.label]));
    $("#evidence-list").innerHTML = observations.map((observation) => {
      const color = COLORS[observation.state] || COLORS.unknown;
      const stateLabel = observation.state === "energized" ? "带电" : observation.state === "outage" ? "停电" : "未知";
      return `<div class="evidence">
        <i class="state-dot" style="background:${color};box-shadow:0 0 7px ${color}"></i>
        <div><div class="node-name">${escapeXml(labels.get(observation.node_id) || observation.node_id)}</div><div class="result-section">${escapeXml(observation.node_id)}</div></div>
        <div class="evidence-meta">${stateLabel}<br>${observation.observed_at}s · ${(observation.confidence * 100).toFixed(0)}%</div>
      </div>`;
    }).join("");
  }

  function renderScenarioList() {
    $("#scenario-list").innerHTML = scenarios.map((scenario, index) => `
      <button class="scenario ${scenario.id === state.scenario?.id ? "active" : ""}" data-scenario="${index}" type="button">
        <span class="mini-kicker">${escapeXml(scenario.eyebrow)}</span>
        <strong>${escapeXml(scenario.name)}</strong>
        <small>${escapeXml(scenario.description)}</small>
      </button>`).join("");
  }

  function selectScenario(index) {
    state.scenario = scenarios[index];
    state.selectedCandidate = 0;
    history.replaceState(null, "", `#${state.scenario.id}`);
    renderScenarioList();
    renderMap();
    renderInspector();
  }

  document.addEventListener("click", (event) => {
    const scenario = event.target.closest("[data-scenario]");
    if (scenario) {
      selectScenario(Number(scenario.dataset.scenario));
      return;
    }
    const candidate = event.target.closest("[data-candidate]");
    if (candidate) {
      state.selectedCandidate = Number(candidate.dataset.candidate);
      renderMap();
      renderInspector();
    }
  });

  $("#download-json").addEventListener("click", () => {
    const blob = new Blob([JSON.stringify(state.scenario, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `gridlatch-${state.scenario.id}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
  });

  if (scenarios.length) {
    const requested = scenarios.findIndex((scenario) => `#${scenario.id}` === location.hash);
    selectScenario(requested >= 0 ? requested : 0);
  }
})();
