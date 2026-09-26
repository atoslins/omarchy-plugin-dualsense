"""Shared by the tests: the repository root and a loader for the
extension-less Python scripts in bin/ and udev/."""

import importlib.machinery
import importlib.util
import json
import os
import sys

# Importing an extension-less script leaves "<name>cpython-3XX.pyc" behind in
# bin/__pycache__, inside the folder the plugin runs from.
sys.dont_write_bytecode = True

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(relpath, name):
    path = os.path.join(ROOT, relpath)
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def manifest():
    with open(os.path.join(ROOT, "manifest.json")) as f:
        return json.load(f)
