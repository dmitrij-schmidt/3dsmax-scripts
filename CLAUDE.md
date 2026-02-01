# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MaxScript tools and automation scripts for Autodesk 3ds Max with V-Ray. This is a production pipeline tooling repo — scripts here are used by artists in real environments with large, messy, production-critical scenes.

## Domain Context

- **Language:** MaxScript (`.ms`, `.mcr` files)
- **Target application:** Autodesk 3ds Max
- **Renderer:** V-Ray (VRayMtl, VRayBlendMtl, VRay2SidedMtl, render elements, proxies)
- **File I/O:** INI, TXT, JSON (via dotNet)

## Code Standards

- Write clean, modular, reusable MaxScript using structs, rollout UIs, macroscripts, callbacks
- Defensive scripting: error handling, logging, version compatibility
- Performance-aware: minimize loops, use lazy evaluation, account for scene scale
- Always produce complete, runnable scripts — not fragments or pseudocode
- Comment non-obvious logic; state supported 3ds Max versions, V-Ray version assumptions, and known limitations
- Prefer non-destructive workflows (layers, instances, overrides)
- Assume backward compatibility concerns with older 3ds Max versions

## Key Constraints

- Never perform destructive operations (geometry/material modifications) without explicit confirmation
- Assume scenes may be large, legacy, broken, or inconsistent (bad paths, wrong units, unsupported materials)
- Optimize for production reliability and repeatability, not tutorials
- When debugging: isolate the issue, inspect scene state/node properties/renderer settings, reason about root cause (script logic, scene corruption, renderer config, or user misuse)
