# LyriaFlow Plans & Architecture Notes

This directory houses technical design documents, feature plans, architecture decision records (ADRs), and development roadmaps for LyriaFlow.

---

## Directory Structure

```
docs/
├── user-guide.md          # Comprehensive user manual & operation guide
└── plans/
    ├── README.md          # This index and plan authoring guide
    └── templates/
        └── feature-plan.md # Standard scaffold for new features
```

---

## Plan Authoring Guidelines

When creating a new feature plan or architecture proposal, follow this format:

1. **Context & Goals**: High-level problem statement and objectives.
2. **Architecture & Changes**: Component breakdown (Models, Services, ViewModels, Views).
3. **Audio & Protocol Considerations**: Impact on `mcp-lyria-go` stdio protocol, Gemini schemas, or `AVAudioPlayer` audio pipelines.
4. **Acceptance Criteria & Verification Plan**: Automated test assertions and manual test flows.
