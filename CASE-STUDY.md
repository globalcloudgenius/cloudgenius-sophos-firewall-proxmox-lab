# Case Study — Sophos Firewall on Proxmox

## Status

**In progress.**

This document intentionally distinguishes planned architecture from validated implementation.

## Executive summary

This project demonstrates an enterprise-style firewall architecture on Proxmox using Sophos Firewall as a virtual security control plane.

The design covers network segmentation, policy enforcement, remote connectivity, monitoring, administration, and recoverability.

## Business problem

Flat networks offer little control over lateral movement, administrative exposure, or workload separation.

A dedicated firewall architecture introduces clear security boundaries and creates a realistic foundation for hybrid-cloud and security operations.

## Target capabilities

The project is designed to cover:

- WAN / LAN / DMZ / guest / management segmentation;
- least-privilege inter-zone rules;
- NAT and approved publishing;
- secure administration;
- VPN scenarios;
- monitoring and reporting;
- configuration backup and recovery;
- automated VM deployment.

## Engineering approach

The repository includes automation for validating Proxmox prerequisites, creating the VM, importing Sophos disks, attaching interfaces, and validating configuration before power-on.

## Why the status matters

A trustworthy portfolio should not present planned controls as completed controls.

Items that are validated are documented as complete. Items still under development remain explicitly marked as in progress.

## Consulting relevance

The same architecture and engineering practices apply to:

- network-security assessments;
- firewall modernization;
- segmentation design;
- secure management-plane design;
- VPN and hybrid connectivity;
- virtualization security;
- operational recovery planning.

## Evidence

See the main [README](./README.md) and deployment scripts in the repository.

## Engagement fit

Relevant for:

- firewall architecture;
- Proxmox / KVM security;
- segmentation;
- secure remote access;
- hybrid networking;
- security control-plane design.

**Consulting inquiries:** advisory@cloudgenius.ca
