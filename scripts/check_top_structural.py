import os
import re
import glob

def extract_module_ports(filepath):
    """Extract module name, parameters, and port declarations from a verilog file."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Strip single line comments
    content = re.sub(r'//.*', '', content)
    # Strip multi line comments
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)

    # Find module declaration: module <name> #(...) (...); or module <name> (...);
    mod_match = re.search(r'\bmodule\s+(\w+)\s*(?:#\s*\((.*?)\)\s*)?\((.*?)\);', content, re.DOTALL)
    if not mod_match:
        return None

    mod_name = mod_match.group(1)
    port_text = mod_match.group(3)

    ports = {}
    port_entries = port_text.split(',')
    for entry in port_entries:
        entry = entry.strip()
        if not entry:
            continue
        p_match = re.search(r'(input|output|inout)\s+(?:wire|reg)?\s*(?:\[([^\]]+)\])?\s*(\w+)', entry)
        if p_match:
            p_dir = p_match.group(1)
            p_width = p_match.group(2) if p_match.group(2) else "1"
            p_name = p_match.group(3)
            ports[p_name] = {'dir': p_dir, 'width': p_width}

    return mod_name, ports

def parse_instantiations(top_file):
    """Parse all module instantiations in top_file."""
    with open(top_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # Strip comments
    content = re.sub(r'//.*', '', content)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)

    # Remove the top module header
    content = re.sub(r'\bmodule\s+\w+\s*(?:#\s*\(.*?\)\s*)?\(.*?\);', '', content, flags=re.DOTALL)
    content = re.sub(r'\bendmodule\b', '', content)

    # Find instantiations
    inst_pattern = r'\b(\w+)\s*(?:#\s*\((.*?)\)\s*)?(\w+)\s*\((.*?)\);'
    insts = []
    keywords = {'module', 'endmodule', 'begin', 'end', 'if', 'else', 'case', 'endcase', 'always', 'assign', 'wire', 'reg', 'localparam', 'parameter'}
    for match in re.finditer(inst_pattern, content, re.DOTALL):
        mod_type = match.group(1)
        inst_name = match.group(3)
        port_conns_str = match.group(4)

        if mod_type in keywords:
            continue

        conns = {}
        for conn_match in re.finditer(r'\.(\w+)\s*\(\s*(.*?)\s*\)', port_conns_str, re.DOTALL):
            p_name = conn_match.group(1)
            net_name = conn_match.group(2).strip()
            conns[p_name] = net_name

        insts.append({
            'module': mod_type,
            'instance': inst_name,
            'connections': conns
        })
    return insts

def check_all():
    rtl_files = glob.glob('rtl/*.v') + glob.glob('rtl/datapath/*.v') + glob.glob('rtl/memory/*.v')
    defined_modules = {}
    for f in rtl_files:
        res = extract_module_ports(f)
        if res:
            name, ports = res
            defined_modules[name] = {'file': f, 'ports': ports}

    top_file = 'rtl/top_structural.v'
    insts = parse_instantiations(top_file)

    errors = []
    warnings = []

    print(f"Checking {top_file}...")
    print(f"Found {len(insts)} module instances in top_structural.v:\n")
    for i, inst in enumerate(insts, 1):
        print(f"  {i:2d}. {inst['instance']} : {inst['module']} ({len(inst['connections'])} ports connected)")

    for inst in insts:
        m_type = inst['module']
        i_name = inst['instance']
        conns = inst['connections']

        if m_type not in defined_modules:
            errors.append(f"ERROR: Instance '{i_name}' uses undefined module '{m_type}'")
            continue

        def_ports = defined_modules[m_type]['ports']

        # Check all connected ports exist on the module
        for p_name, net in conns.items():
            if p_name not in def_ports:
                errors.append(f"ERROR in '{i_name}' ({m_type}): Port '.{p_name}' does not exist on module '{m_type}'!")

        # Check all required ports on the module are connected
        for p_name in def_ports:
            if p_name not in conns:
                warnings.append(f"WARNING in '{i_name}' ({m_type}): Module port '{p_name}' is not connected in {top_file}")

    print("\n========================================")
    print("VERIFICATION RESULTS:")
    print("========================================")
    if errors:
        print(f"FAILED with {len(errors)} error(s):")
        for e in errors:
            print(f"  [x] {e}")
    else:
        print("  [SUCCESS] 0 port mismatch errors!")

    if warnings:
        print(f"\n{len(warnings)} warning(s):")
        for w in warnings:
            print(f"  [!] {w}")
    else:
        print("  [SUCCESS] All module ports are 100% connected!")

if __name__ == '__main__':
    check_all()
