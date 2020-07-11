# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@com_google_api_codegen//rules_gapic:gapic_pkg.bzl", "construct_package_dir_paths")

def _py_gapic_src_pkg_impl(ctx):
    srcjar_srcs = []
    for dep in ctx.attr.deps:
        for f in dep.files.to_list():
            if f.extension in ("srcjar", "jar", "zip"):
                srcjar_srcs.append(f)

    paths = construct_package_dir_paths(ctx.attr.package_dir, ctx.outputs.pkg, ctx.label.name)

    script = """
    mkdir -p {package_dir_path}
    for srcjar_src in {srcjar_srcs}; do
        unzip -q -o $srcjar_src -d {package_dir_path}
    done
    cd {package_dir_path}/..
    tar -zchpf {package_dir}/{package_dir}.tar.gz {package_dir}
    cd -
    mv {package_dir_path}/{package_dir}.tar.gz {pkg}
    rm -rf {package_dir_path}
    """.format(
        srcjar_srcs = " ".join(["'%s'" % f.path for f in srcjar_srcs]),
        package_dir_path = paths.package_dir_path,
        package_dir = paths.package_dir,
        pkg = ctx.outputs.pkg.path,
        package_dir_expr = paths.package_dir_expr,
    )

    ctx.actions.run_shell(
        inputs = srcjar_srcs,
        command = script,
        outputs = [ctx.outputs.pkg],
    )

def _py_gapic_postprocessed_srcjar_impl(ctx):
    gapic_srcjar = ctx.file.gapic_srcjar
    formatter = ctx.executable.formatter
    output_dir_name = ctx.label.name

    output_main = ctx.outputs.main
    output_test = ctx.outputs.test
    output_smoke_test = ctx.outputs.smoke_test
    output_pkg = ctx.outputs.pkg
    outputs = [output_main, output_test, output_smoke_test, output_pkg]

    output_dir_path = "%s/%s" % (output_main.dirname, output_dir_name)

    # Note the script is more complicated than it intuitively should be because of limitations
    # inherent to bazel execution environment: no absolute paths allowed, the generated artifacts
    # must ensure uniqueness within a build.
    script = """
    unzip -q {gapic_srcjar} -d {output_dir_path}
    {formatter} -q {output_dir_path}
    pushd {output_dir_path}
    zip -q -r {output_dir_name}-pkg.srcjar noxfile.py setup.py setup.cfg docs MANIFEST.in README.rst LICENSE
    rm -rf noxfile.py setup.py docs
    zip -q -r {output_dir_name}-test.srcjar tests/unit
    rm -rf tests/unit
    if [ -d "tests/system" ]; then
        zip -q -r {output_dir_name}-smoke-test.srcjar tests/system
        rm -rf tests/system
    else
        touch empty_file
        zip -q -r {output_dir_name}-smoke-test.srcjar empty_file
        zip -d {output_dir_name}-smoke-test.srcjar empty_file
    fi
    zip -q -r {output_dir_name}.srcjar . -i \*.py
    popd
    mv {output_dir_path}/{output_dir_name}.srcjar {output_main}
    mv {output_dir_path}/{output_dir_name}-test.srcjar {output_test}
    mv {output_dir_path}/{output_dir_name}-smoke-test.srcjar {output_smoke_test}
    mv {output_dir_path}/{output_dir_name}-pkg.srcjar {output_pkg}
    rm -rf {output_dir_path}
    """.format(
        gapic_srcjar = gapic_srcjar.path,
        output_dir_name = output_dir_name,
        output_dir_path = output_dir_path,
        formatter = formatter.path,
        output_main = output_main.path,
        output_test = output_test.path,
        output_smoke_test = output_smoke_test.path,
        output_pkg = output_pkg.path,
    )

    ctx.actions.run_shell(
        inputs = [gapic_srcjar],
        command = script,
        outputs = outputs,
    )

    return [
        DefaultInfo(
            files = depset(direct = outputs),
        ),
        GapicInfo(
            main = output_main,
            test = output_test,
            smoke_test = output_smoke_test,
            pkg = output_pkg,
        ),
    ]
    
_py_gapic_postprocessed_srcjar = rule(
    implementation = _py_gapic_postprocessed_srcjar_impl,
    attrs = {
        "gapic_srcjar": attr.label(
            doc = "The srcjar of the generated GAPIC client.",
            mandatory = True,
            allow_single_file = True,
        ),
        "formatter": attr.label(
            doc = "Formats the output to a Python-idiomatic style.",
            default = Label("@pypi_black//:black"),
            executable = True,
            cfg = "host",
        ),
    },
    outputs = {
        "main": "%{name}.srcjar",
        "test": "%{name}-test.srcjar",
        "smoke_test": "%{name}-smoke-test.srcjar",
        "pkg": "%{name}-pkg.srcjar",
    },
    doc = """Runs Python-specific post-processing for the generated GAPIC
    client.
    Post-processing includes running the formatter and splitting the main and
    test packages.
    """,
)
    
_py_gapic_src_pkg = rule(
    attrs = {
        "deps": attr.label_list(allow_files = True, mandatory = True),
        "package_dir": attr.string(mandatory = True),
    },
    outputs = {"pkg": "%{name}.tar.gz"},
    implementation = _py_gapic_src_pkg_impl,
)

def py_gapic_assembly_pkg(name, deps, assembly_name = None, **kwargs):
    package_dir = name
    if assembly_name:
        package_dir = "%s-%s" % (assembly_name, name)
    _py_gapic_src_pkg(
        name = name,
        deps = deps,
        package_dir = package_dir,
        **kwargs
    )


