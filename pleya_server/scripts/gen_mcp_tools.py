#!/usr/bin/env python3
"""Leid het MCP-toolregister af uit de bestaande protocoloperaties."""
import argparse
import json
from pathlib import Path
import re
import sys

import yaml

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / 'docs/pleya-protocol/v1/openapi.yaml'
OUTPUT = ROOT / 'pleya_server/internal/mcp/operations.json'
POLICY = Path(__file__).with_name('mcp_policy.json')


def generate(spec, policy=None):
    policy = json.loads(POLICY.read_text()) if policy is None else policy
    def resolve(value):
        while isinstance(value, dict) and '$ref' in value:
            target = spec
            for part in value['$ref'].removeprefix('#/').split('/'):
                target = target[part]
            value = target
        return value

    def schema(value, definitions):
        if isinstance(value, list):
            return [schema(v, definitions) for v in value]
        if not isinstance(value, dict):
            return value
        if '$ref' in value:
            ref = value['$ref']
            assert ref.startswith('#/components/schemas/'), ref
            name = ref.rsplit('/', 1)[1]
            if name not in definitions:
                definitions[name] = {}
                definitions[name] = schema(resolve(value), definitions)
            return {'$ref': '#/$defs/' + name}
        return {k: schema(v, definitions) for k, v in value.items()}

    tools = []
    names = set()
    for path, entry in spec['paths'].items():
        for method, operation in entry.items():
            if method not in {'get', 'post', 'put', 'patch', 'delete', 'head', 'options'}:
                continue
            name = operation['operationId']
            assert re.fullmatch(r'[A-Za-z0-9_-]{1,128}', name) and name not in names, name
            names.add(name)
            assert name in policy, f'ongeclassificeerde operatie: {name}'
            rule = policy[name]
            assert rule.get('method') == method.upper() and rule.get('path') == path, f'classificatie verouderd: {name}'
            assert rule.get('access') in {'read', 'blocked'} and rule.get('reason', '').strip(), f'onvolledige classificatie: {name}'
            if rule['access'] == 'blocked':
                continue
            assert method == 'get' and (operation.get('security') != [] or name == 'getInfo'), f'onveilige leestool: {name}'
            definitions = {}
            properties = {}
            required = []
            parameters = [resolve(p) for p in entry.get('parameters', []) + operation.get('parameters', [])]
            for location in ('path', 'query', 'header'):
                selected = [p for p in parameters if p['in'] == location]
                if not selected:
                    continue
                group = {'type': 'object', 'properties': {p['name']: schema(p['schema'], definitions) for p in selected}, 'additionalProperties': False}
                needed = [p['name'] for p in selected if p.get('required')]
                if needed:
                    group['required'] = needed
                    required.append(location)
                properties[location] = group
            if 'requestBody' in operation:
                body = resolve(operation['requestBody'])
                assert set(body['content']) == {'application/json'}, name
                properties['body'] = schema(body['content']['application/json']['schema'], definitions)
                if body.get('required'):
                    required.append('body')
            destructive = False
            inputs = {'type': 'object', 'properties': properties, 'additionalProperties': False}
            if required:
                inputs['required'] = required
            if definitions:
                inputs['$defs'] = definitions
            tools.append({'name': name, 'method': method.upper(), 'path': path, 'destructive': destructive, 'description': operation.get('description', operation.get('summary', name)), 'inputSchema': inputs})
    assert names == set(policy), 'classificatie bevat verwijderde operaties'
    return sorted(tools, key=lambda t: t['name'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    tools = generate(yaml.safe_load(CONTRACT.read_text()))
    result = json.dumps(tools, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != result:
            print('MCP-register wijkt af van OpenAPI', file=sys.stderr)
            return 1
    else:
        OUTPUT.write_text(result)
    print(f'MCP-register: {len(tools)} operaties gecontroleerd' if args.check else f'MCP-register: {len(tools)} operaties gegenereerd')
    return 0


if __name__ == '__main__':
    sys.exit(main())
