# Wires the smart choice (urltest_smart.go) into the copy of sing-box: its options, the state of a group and the hooks.
# Run by patch-singbox.sh from core/.
import io


def read(p):
    return io.open(p, encoding="utf8").read()


def write(p, s):
    io.open(p, "w", encoding="utf8", newline="\n").write(s)


# the options of a group
p = "patched/sing-box/option/group.go"
s = read(p)
a = '\tInterruptExistConnections bool               `json:"interrupt_exist_connections,omitempty"`\n}'
assert a in s, "group options"
s = s.replace(
    a,
    '\tInterruptExistConnections bool               `json:"interrupt_exist_connections,omitempty"`\n'
    '\tSmart                     bool               `json:"smart,omitempty"`\n'
    '\tSmartDwell                badoption.Duration `json:"smart_dwell,omitempty"`\n'
    '\tSmartGainMs               uint16             `json:"smart_gain_ms,omitempty"`\n'
    '\tSmartGainPct              uint16             `json:"smart_gain_pct,omitempty"`\n'
    '\tSmartCountryPct           uint16             `json:"smart_country_pct,omitempty"`\n'
    '\tSmartWindow               uint16             `json:"smart_window,omitempty"`\n'
    '\tSmartActive               uint16             `json:"smart_active,omitempty"`\n'
    '\tSmartExplore              uint16             `json:"smart_explore,omitempty"`\n'
    '\tSmartFull                 badoption.Duration `json:"smart_full,omitempty"`\n'
    '\tSmartWarm                 badoption.Duration `json:"smart_warm,omitempty"`\n'
    '\tSmartPoints               bool               `json:"smart_points,omitempty"`\n'
    '\tSmartGainPts              uint16             `json:"smart_gain_pts,omitempty"`\n'
    '\tSmartCountryPts           uint16             `json:"smart_country_pts,omitempty"`\n'
    '\tSmartHabit                uint16             `json:"smart_habit,omitempty"`\n'
    '\tSmartMemory               string             `json:"smart_memory,omitempty"`\n'
    '\tSmartPins                 string             `json:"smart_pins,omitempty"`\n'
    '\tPriorityTags              []string           `json:"priority_tags,omitempty"`\n'
    '\tPriorityMargin            uint16             `json:"priority_margin,omitempty"`\n}',
    1,
)
write(p, s)

# the group
p = "patched/sing-box/protocol/group/urltest.go"
s = read(p)


def rep(a, b, n=1):
    global s
    assert a in s, a[:70]
    s = s.replace(a, b, n)


rep(
    "\tinterruptExternalConnections bool\n}\n\nfunc NewURLTest(",
    "\tinterruptExternalConnections bool\n\tsmart                        *smartOptions\n\tpriority                     *priorityOptions\n}\n\nfunc NewURLTest(",
)
rep(
    '\tif len(outbound.tags) == 0 {\n\t\treturn nil, E.New("missing tags")',
    "\tif options.Smart || options.SmartActive > 0 {\n"
    "\t\toutbound.smart = &smartOptions{\n"
    "\t\t\tdwell:      time.Duration(options.SmartDwell),\n"
    "\t\t\tgainMs:     int(options.SmartGainMs),\n"
    "\t\t\tgainPct:    int(options.SmartGainPct),\n"
    "\t\t\tcountryPct: int(options.SmartCountryPct),\n"
    "\t\t\twindow:     int(options.SmartWindow),\n"
    "\t\t\tselects:    options.Smart,\n"
    "\t\t\tactive:     int(options.SmartActive),\n"
    "\t\t\texplore:    int(options.SmartExplore),\n"
    "\t\t\tfullEvery:  time.Duration(options.SmartFull),\n"
    "\t\t\twarm:       time.Duration(options.SmartWarm),\n"
    "\t\t\tpoints:     options.SmartPoints,\n"
    "\t\t\tgainPts:    int(options.SmartGainPts),\n"
    "\t\t\tcountryPts: int(options.SmartCountryPts),\n"
    "\t\t\thabit:      int(options.SmartHabit),\n"
    "\t\t\tmemory:     options.SmartMemory,\n"
    "\t\t\tpins:       options.SmartPins,\n"
    "\t\t}\n"
    "\t}\n"
    "\tif options.PriorityMargin > 0 && len(options.PriorityTags) > 0 {\n"
    "\t\toutbound.priority = &priorityOptions{tags: map[string]bool{}, margin: int(options.PriorityMargin)}\n"
    "\t\tfor _, t := range options.PriorityTags {\n"
    "\t\t\toutbound.priority.tags[t] = true\n"
    "\t\t}\n"
    "\t}\n"
    '\tif len(outbound.tags) == 0 {\n\t\treturn nil, E.New("missing tags")',
)
rep(
    "\t\ts.group = group\n",
    "\t\ts.group = group\n\t\tgroup.priority = s.priority\n\t\tif s.smart != nil {\n\t\t\tgroup.smart = newSmartState(s.logger, s.Tag(), *s.smart)\n\t\t\tgroup.smart.priority = s.priority\n\t\t}\n",
)
rep(
    "\tlastActive                   common.TypedValue[time.Time]\n",
    "\tlastActive                   common.TypedValue[time.Time]\n\tsmart                        *smartState\n\tpriority                     *priorityOptions\n",
)
rep(
    "func (g *URLTestGroup) Select(network string) (adapter.Outbound, bool) {\n",
    "func (g *URLTestGroup) Select(network string) (adapter.Outbound, bool) {\n"
    "\tif g.smart != nil && g.smart.opt.selects {\n\t\treturn g.smartSelect(network)\n\t}\n",
)
rep(
    "\tresult := URLTestOutbounds(ctx, g.outbound, g.history, g.logger, g.outbounds, g.link, g.interval, force)\n\tg.performUpdateCheck()",
    "\ttargets := g.outbounds\n\tif force {\n\t\tg.smartWarmUp()\n\t} else {\n\t\ttargets = g.smartTargets()\n\t}\n\tresult := URLTestOutbounds(ctx, g.outbound, g.history, g.logger, targets, g.link, g.interval, force)\n\tg.smartRound()\n\tg.performUpdateCheck()",
)
rep(
    "\ts.group.history.DeleteURLTestHistory(outbound.Tag())\n\treturn nil, err",
    "\ts.group.history.DeleteURLTestHistory(outbound.Tag())\n\ts.group.smartLost(outbound.Tag())\n\treturn nil, err",
    2,
)
# the plain choice by delay: the others have to be faster by the margin than the main subscription's servers
rep(
    "\tvar minDelay uint16\n\tvar minOutbound adapter.Outbound\n",
    "\tvar minDelay int\n\tvar minOutbound adapter.Outbound\n",
)
rep(
    "\t\t\t\tminOutbound = g.selectedOutboundTCP\n\t\t\t\tminDelay = history.Delay\n",
    "\t\t\t\tminOutbound = g.selectedOutboundTCP\n\t\t\t\tminDelay = int(history.Delay) + g.priority.penalty(g.selectedOutboundTCP.Tag())\n",
)
rep(
    "\t\t\t\tminOutbound = g.selectedOutboundUDP\n\t\t\t\tminDelay = history.Delay\n",
    "\t\t\t\tminOutbound = g.selectedOutboundUDP\n\t\t\t\tminDelay = int(history.Delay) + g.priority.penalty(g.selectedOutboundUDP.Tag())\n",
)
rep(
    "\t\tif minDelay == 0 || minDelay > history.Delay+g.tolerance {\n\t\t\tminDelay = history.Delay\n\t\t\tminOutbound = detour\n\t\t}\n",
    "\t\teffective := int(history.Delay) + g.priority.penalty(detour.Tag())\n\t\tif minDelay == 0 || minDelay > effective+int(g.tolerance) {\n\t\t\tminDelay = effective\n\t\t\tminOutbound = detour\n\t\t}\n",
)
write(p, s)
print("smart patch applied")
