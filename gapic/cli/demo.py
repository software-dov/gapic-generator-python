#!/usr/bin/env python3
# Copyright (C) 2019  Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import click
import jinja2
import os
import yaml

from collections import Counter

from google.protobuf.compiler import plugin_pb2

from gapic import utils
from gapic.generator import options
from gapic.samplegen import samplegen
from gapic.schema import api


def setup_jinja_env(templates_dir):
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(searchpath=templates_dir),
        undefined=jinja2.StrictUndefined,
        extensions=["jinja2.ext.do"],
        trim_blocks=True,
        lstrip_blocks=True,
    )

    # Add filters which templates require.
    env.filters['rst'] = utils.rst
    env.filters['snake_case'] = utils.to_snake_case
    env.filters['sort_lines'] = utils.sort_lines
    env.filters['wrap'] = utils.wrap
    env.filters['coerce_response_name'] = samplegen.coerce_response_name

    return env


@click.command()
@click.option("--sampleconfig", "sampleconfig_fpath", type=str,
              help="Path to the sample config yaml file.")
@click.option("--serialized-proto", "serialized_proto_fpath", type=str,
              help="Path to the serialized protobuf")
@click.option("--template-dir", "template_dir", type=str,
              help="Path to directory full of jinja templates")
def demo(sampleconfig_fpath, serialized_proto_fpath, template_dir):
    with open(sampleconfig_fpath, "rb") as f:
        sampleconfig = yaml.safe_load(f.read())

    with open(serialized_proto_fpath, "rb") as f:
        serialzied_proto = f.read()

    req = plugin_pb2.CodeGeneratorRequest.FromString(serialzied_proto)
    opts = options.Options.build(req.parameter)
    package = os.path.commonprefix([i.package
                                    for i in req.proto_file
                                    if i.name in req.file_to_generate]).rstrip(".")
    api_schema = api.API.build(req.proto_file, opts=opts, package=package)
    is_unique_ctr = Counter(sample["id"] for sample in sampleconfig["samples"])
    jinja_env = setup_jinja_env(template_dir)
    fpath_to_sample = {}

    for sample in sampleconfig["samples"]:
        sample_fpath, streamed_sample = samplegen.generate_sample(
            sample,
            # If the id is unique, the counter only registers 1 hit for it.
            # Take that 1 away, turn it into a 'has-duplicates' bool, then negate.
            not bool(is_unique_ctr[sample["id"]] - 1),
            jinja_env,
            api_schema)
        fpath_to_sample[sample_fpath] = sample
        with open(sample_fpath, "w") as f:
            for block in streamed_sample:
                f.write(block)

    manifest_fname, manifest = samplegen.generate_manifest(fpath_to_sample.items(), api_schema)
    with open(manifest_fname, "w") as f:
        f.write("\n".join(s.render() for s in manifest))


if __name__ == "__main__":
    demo()
