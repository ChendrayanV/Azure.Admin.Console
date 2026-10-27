# The Architecture area: design-time support for Azure architects - probe
# questions, pattern selection, a design model, its validation against the
# Well-Architected Framework, Azure Policy, guardrails and PSRule, diagrams and
# decision records. It works offline; only -LandingZone reads Azure.
@{
    Name        = 'Architecture'
    Title       = 'Architecture design'
    Description = 'Design-time commands for Azure architects: probe questions that capture the requirements, cloud design patterns ranked against them, a design model, its validation against the Well-Architected Framework, inherited Azure Policy, guardrails and PSRule for Azure, Mermaid and draw.io diagrams with compliance layers, and architecture decision records.'
    Order       = 4
    DependsOn   = @('Core')
}
