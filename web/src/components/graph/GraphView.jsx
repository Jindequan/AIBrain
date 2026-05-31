import { useMemo, useCallback, useState, useRef, useEffect } from 'react'

const NODE_COLORS = {
  goal: { bg: '#6366f1', border: '#4f46e5', text: '#fff' },
  task: { bg: '#8b5cf6', border: '#7c3aed', text: '#fff' },
  event: { bg: '#f59e0b', border: '#d97706', text: '#fff' },
  action: { bg: '#0ea5e9', border: '#0284c7', text: '#fff' },
}

const NODE_RADII = {
  goal: 28,
  task: 22,
  event: 14,
  action: 16,
}

const ARROW_ID = 'graph-arrow'

// ─── Tree Layout (top-down hierarchy) ──────────────────────────

function treeLayout(nodes, edges, width, height) {
  if (nodes.length === 0) return []
  if (nodes.length === 1) return [{ x: width / 2, y: height / 2 }]

  const padX = 80, padY = 60

  // Build children map from edges
  const children = {}
  const hasParent = {}
  nodes.forEach(n => { children[n.id] = [] })
  edges.forEach(e => {
    if (children[e.source]) children[e.source].push(e.target)
    hasParent[e.target] = true
  })

  // Find roots
  const roots = nodes.filter(n => !hasParent[n.id]).map(n => n.id)
  if (roots.length === 0) roots.push(nodes[0].id)

  // BFS to compute depth and topological order
  const depth = {}
  const order = []
  const queue = roots.map(id => ({ id, d: 0 }))
  let qi = 0
  while (qi < queue.length) {
    const { id, d } = queue[qi++]
    if (depth[id] !== undefined) continue
    depth[id] = d
    order.push(id)
    ;(children[id] || []).forEach(c => {
      if (depth[c] === undefined) queue.push({ id: c, d: d + 1 })
    })
  }
  // Assign default depth for disconnected nodes
  nodes.forEach(n => { if (depth[n.id] === undefined) depth[n.id] = 0 })

  // Count leaves under each node (for proportional horizontal allocation)
  const leaves = {}
  function countLeaves(id) {
    const kids = children[id] || []
    if (kids.length === 0) return 1
    let total = 0
    kids.forEach(k => { total += countLeaves(k) })
    leaves[id] = total
    return total
  }
  roots.forEach(r => { leaves[r] = countLeaves(r) })

  // Assign x: subdivide the horizontal range proportionally to leaf counts.

  // First, assign each root a proportional slice of the total width.
  // Then recursively subdivide each root's slice among its children.
  const xPos = {}
  const totalRootLeaves = roots.reduce((s, r) => s + Math.max(leaves[r] || 1, 1), 0)
  let curLeft = padX
  roots.forEach(r => {
    const span = (width - padX * 2) * (Math.max(leaves[r] || 1, 1) / totalRootLeaves)
    assignXslice(r, curLeft, curLeft + span)
    curLeft += span
  })

  function assignXslice(id, left, right) {
    const kids = children[id] || []
    if (kids.length === 0) {
      xPos[id] = (left + right) / 2
      return
    }
    const totalLeaves = kids.reduce((s, k) => s + Math.max(leaves[k] || 1, 1), 0)
    let current = left
    kids.forEach(k => {
      const span = (right - left) * (Math.max(leaves[k] || 1, 1) / totalLeaves)
      assignXslice(k, current, current + span)
      current += span
    })
    xPos[id] = (left + right) / 2
  }

  // Position nodes
  const maxDepth = Math.max(1, ...Object.values(depth))
  const availHeight = height - padY * 2
  const yStep = availHeight / maxDepth

  return nodes.map((node) => ({
    x: xPos[node.id] ?? width / 2,
    y: padY + (depth[node.id] ?? 0) * yStep,
  }))
}

// ─── Force-Directed Layout (flat graph) ────────────────────────

function simpleForceLayout(nodes, edges, width, height) {
  const centerX = width / 2
  const centerY = height / 2
  const k = 150

  const positions = nodes.map(() => ({
    x: centerX + (Math.random() - 0.5) * width * 0.3,
    y: centerY + (Math.random() - 0.5) * height * 0.3,
  }))

  for (let iter = 0; iter < 80; iter++) {
    const forces = positions.map(() => ({ fx: 0, fy: 0 }))

    // Repulsion between all pairs
    for (let i = 0; i < nodes.length; i++) {
      for (let j = i + 1; j < nodes.length; j++) {
        const dx = positions[j].x - positions[i].x
        const dy = positions[j].y - positions[i].y
        const dist = Math.max(Math.sqrt(dx * dx + dy * dy), 1)
        const force = k * k / (dist * dist)
        const fx = (dx / dist) * force
        const fy = (dy / dist) * force
        forces[i].fx -= fx
        forces[i].fy -= fy
        forces[j].fx += fx
        forces[j].fy += fy
      }
    }

    // Attraction along edges
    const edgeSet = new Set()
    for (const edge of edges) {
      const key = `${edge.source}-${edge.target}`
      if (edgeSet.has(key)) continue
      edgeSet.add(key)

      const si = nodes.findIndex(n => n.id === edge.source)
      const ti = nodes.findIndex(n => n.id === edge.target)
      if (si === -1 || ti === -1) continue

      const dx = positions[ti].x - positions[si].x
      const dy = positions[ti].y - positions[si].y
      const dist = Math.max(Math.sqrt(dx * dx + dy * dy), 1)
      const force = dist / k * 0.5
      const fx = (dx / dist) * force
      const fy = (dy / dist) * force
      forces[si].fx += fx
      forces[si].fy += fy
      forces[ti].fx -= fx
      forces[ti].fy -= fy
    }

    // Center gravity
    for (let i = 0; i < nodes.length; i++) {
      const dx = centerX - positions[i].x
      const dy = centerY - positions[i].y
      forces[i].fx += dx * 0.01
      forces[i].fy += dy * 0.01
    }

    // Apply forces with damping
    const damping = 0.1 * (1 - iter / 80)
    for (let i = 0; i < nodes.length; i++) {
      positions[i].x += forces[i].fx * damping
      positions[i].y += forces[i].fy * damping
      positions[i].x = Math.max(40, Math.min(width - 40, positions[i].x))
      positions[i].y = Math.max(40, Math.min(height - 40, positions[i].y))
    }
  }

  return positions
}

const LAYOUTS = {
  tree: treeLayout,
  force: simpleForceLayout,
}

export default function GraphView({
  nodes = [],
  edges = [],
  selectedId,
  onNodeClick,
  width = 800,
  height = 500,
  layout = 'tree',
}) {
  const [pan, setPan] = useState({ x: 0, y: 0 })
  const [zoom, setZoom] = useState(1)
  const [dragging, setDragging] = useState(null)
  const [dragStart, setDragStart] = useState(null)
  const svgRef = useRef(null)

  const positions = useMemo(
    () => {
      const fn = LAYOUTS[layout] || treeLayout
      return fn(nodes, edges, width, height)
    },
    [nodes, edges, width, height, layout]
  )

  const onWheel = useCallback((e) => {
    e.preventDefault()
    const delta = e.deltaY > 0 ? 0.9 : 1.1
    setZoom(z => Math.max(0.2, Math.min(5, z * delta)))
  }, [])

  const onMouseDown = useCallback((e) => {
    if (e.target === svgRef.current || e.target.tagName === 'svg') {
      setDragStart({ x: e.clientX - pan.x, y: e.clientY - pan.y })
      setDragging('pan')
    }
  }, [pan])

  const onMouseMove = useCallback((e) => {
    if (dragging === 'pan' && dragStart) {
      setPan({ x: e.clientX - dragStart.x, y: e.clientY - dragStart.y })
    }
  }, [dragging, dragStart])

  const onMouseUp = useCallback(() => {
    setDragging(null)
    setDragStart(null)
  }, [])

  useEffect(() => {
    window.addEventListener('mouseup', onMouseUp)
    return () => window.removeEventListener('mouseup', onMouseUp)
  }, [onMouseUp])

  const nodePositions = useMemo(() => {
    const posMap = {}
    nodes.forEach((node, i) => {
      posMap[node.id] = positions[i] || { x: width / 2, y: height / 2 }
    })
    return posMap
  }, [nodes, positions, width, height])

  return (
    <svg
      ref={svgRef}
      width={width}
      height={height}
      className="bg-gray-50 rounded-lg cursor-grab active:cursor-grabbing select-none"
      onWheel={onWheel}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      style={{ overflow: 'hidden' }}
    >
      <defs>
        <marker
          id={ARROW_ID}
          viewBox="0 0 10 10"
          refX="10"
          refY="5"
          markerWidth="6"
          markerHeight="6"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#94a3b8" />
        </marker>
      </defs>
      <g transform={`translate(${pan.x},${pan.y}) scale(${zoom})`}>
        {/* Edges */}
        {edges.map((edge, i) => {
          const src = nodePositions[edge.source]
          const tgt = nodePositions[edge.target]
          if (!src || !tgt) return null

          const dx = tgt.x - src.x
          const dy = tgt.y - src.y
          const dist = Math.sqrt(dx * dx + dy * dy) || 1

          const srcR = NODE_RADII[nodes.find(n => n.id === edge.source)?.type || 'task'] || 16
          const tgtR = NODE_RADII[nodes.find(n => n.id === edge.target)?.type || 'task'] || 16

          const sx = src.x + (dx / dist) * srcR
          const sy = src.y + (dy / dist) * srcR
          const tx = tgt.x - (dx / dist) * tgtR
          const ty = tgt.y - (dy / dist) * tgtR

          return (
            <line
              key={`edge-${i}`}
              x1={sx}
              y1={sy}
              x2={tx}
              y2={ty}
              stroke="#94a3b8"
              strokeWidth={1.5}
              markerEnd={`url(#${ARROW_ID})`}
            />
          )
        })}

        {/* Nodes */}
        {nodes.map((node, i) => {
          const pos = positions[i]
          if (!pos) return null
          const colors = NODE_COLORS[node.type] || NODE_COLORS.task
          const r = NODE_RADII[node.type] || 16
          const isSelected = selectedId === node.id

          return (
            <g
              key={node.id}
              transform={`translate(${pos.x},${pos.y})`}
              style={{ cursor: 'pointer' }}
              onClick={(e) => {
                e.stopPropagation()
                onNodeClick?.(node)
              }}
            >
              {isSelected && (
                <circle
                  r={r + 4}
                  fill="none"
                  stroke="#6366f1"
                  strokeWidth={2.5}
                  opacity={0.6}
                />
              )}
              <circle
                r={r}
                fill={colors.bg}
                stroke={isSelected ? colors.border : 'none'}
                strokeWidth={2}
                className="transition-all duration-150"
              />
              <text
                textAnchor="middle"
                dy="0.35em"
                fill={colors.text}
                fontSize={r > 20 ? 11 : 9}
                fontWeight={600}
                style={{ pointerEvents: 'none' }}
              >
                {node.label?.[0]?.toUpperCase() || '?'}
              </text>
              <title>
                {node.label}{node.subtitle ? `\n${node.subtitle}` : ''}{node.status ? `\nStatus: ${node.status}` : ''}
              </title>
            </g>
          )
        })}

        {/* Labels */}
        {nodes.map((node, i) => {
          const pos = positions[i]
          if (!pos) return null
          return (
            <text
              key={`label-${node.id}`}
              x={pos.x}
              y={pos.y + (NODE_RADII[node.type] || 16) + 14}
              textAnchor="middle"
              fill="#374151"
              fontSize={10}
              style={{ pointerEvents: 'none' }}
              className="select-none"
            >
              {node.label}
            </text>
          )
        })}
      </g>
    </svg>
  )
}
