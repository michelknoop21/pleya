#!/usr/bin/env python3
import unittest
from gen_mcp_tools import generate


def rule(method='GET', path='/items/{id}', access='read'):
    return dict(method=method,path=path,access=access,reason='Fixture classification')


class ToolGenerationTests(unittest.TestCase):
    def test_required_refs_and_closed_read_schema(self):
        spec={'components':{'schemas':{'Id':{'type':'string','format':'uuid'}}},'paths':{
            '/items/{id}':{'get':{'operationId':'getItem','parameters':[
                {'name':'id','in':'path','required':True,'schema':{'$ref':'#/components/schemas/Id'}}]}}}}
        operation,=generate(spec,{'getItem':rule()})
        schema=operation['inputSchema']
        self.assertEqual(schema['required'],['path'])
        self.assertEqual(schema['properties']['path']['required'],['id'])
        self.assertEqual(schema['$defs']['Id']['format'],'uuid')
        self.assertFalse(schema['additionalProperties'])
        self.assertFalse(operation['destructive'])
        self.assertNotIn('confirm',schema['properties'])

    def test_blocked_mutations_and_credentials_have_no_schema(self):
        spec={'paths':{'/users':{'post':{'operationId':'createUser'}}}}
        self.assertEqual(generate(spec,{'createUser':rule('POST','/users','blocked')}),[])

    def test_unknown_get_and_post_fail_closed(self):
        for method in ('get','post'):
            with self.subTest(method=method),self.assertRaisesRegex(AssertionError,'ongeclassificeerde'):
                generate({'paths':{'/future':{method:{'operationId':'future'}}}},{})

    def test_changed_method_or_path_requires_review(self):
        spec={'paths':{'/future':{'get':{'operationId':'future'}}}}
        for value in (rule('POST','/future'),rule('GET','/old')):
            with self.assertRaisesRegex(AssertionError,'verouderd'):generate(spec,{'future':value})

    def test_missing_reason_rejected(self):
        value=rule(path='/future');value['reason']=''
        with self.assertRaisesRegex(AssertionError,'onvolledige'):
            generate({'paths':{'/future':{'get':{'operationId':'future'}}}},{'future':value})

    def test_unsafe_read_classification_rejected(self):
        for op in ({'post':{'operationId':'future'}},{'get':{'operationId':'future','security':[]}}):
            with self.assertRaisesRegex(AssertionError,'onveilige'):
                generate({'paths':{'/future':op}},{'future':rule(next(iter(op)).upper(),'/future')})

    def test_removed_operation_rejected(self):
        with self.assertRaisesRegex(AssertionError,'verwijderde'):generate({'paths':{}},{'old':rule()})

    def test_duplicate_operation_rejected(self):
        with self.assertRaises(AssertionError):
            generate({'paths':{'/a':{'get':{'operationId':'read'}},'/b':{'get':{'operationId':'read'}}}}, {'read':rule(path='/a')})


if __name__=='__main__':unittest.main()
