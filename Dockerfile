FROM rust:latest AS builder

# refs
# - https://github.com/godot-rust/godot-rust/issues/647
# - https://github.com/orion78fr/godot_keepass_rust_totp/actions/runs/900998393/workflow#L255

# installation
RUN apt update && apt install -y build-essential clang python3 && \
    git clone https://github.com/emscripten-core/emsdk.git && \
    rustup target add wasm32-unknown-emscripten
WORKDIR /emsdk
RUN git pull && ./emsdk install 2.0.17 && ./emsdk activate 2.0.17
WORKDIR /

# hack about wasm-opt
RUN mv /emsdk/upstream/bin/wasm-opt /emsdk/upstream/bin/wasm-opt-bak \
&& echo -n "\
$(echo '#')!/bin/bash\n\
/emsdk/upstream/bin/wasm-opt-bak \$@ -all\n\
" > /emsdk/upstream/bin/wasm-opt && chmod +x /emsdk/upstream/bin/wasm-opt

# prepare emcc-test (linker)
RUN echo -n "\
$(echo '#')!/bin/bash\n\
\n\
arr=()\n\
\n\
for f in \"\$@\"; do\n\
    if [[ \"\$f\" == *.rlib ]]; then\n\
        #echo Extracting \$f\n\
        \n\
        ar --output \"\$(dirname \$f)\" -x \$f\n\
        \n\
        ar -t \$f | grep .o | while read o; do\n\
            fo=\$(dirname \$f)/\$o\n\
            \n\
            #echo File \$fo\n\
            arr+=(\"\$fo\")\n\
        done\n\
    else\n\
        #echo Passing arg \$f\n\
        arr+=(\"\$f\")\n\
    fi\n\
done\n\
\n\
emcc \${arr[@]}\n\
" > emcc-test && chmod +x emcc-test

ENV C_INCLUDE_PATH="/emsdk/upstream/emscripten/cache/sysroot/include/"
ENV EMMAKEN_CFLAGS="-s SIDE_MODULE=1 -shared -Wl,--no-check-features -all"

RUN echo -n '\
[profile.release]\n\
opt-level = "s"\n\
overflow-checks = false\n\
debug-assertions = false\n\
lto = true\n\
panic = "abort"\n\
\n\
[target.wasm32-unknown-emscripten]\n\
linker = "/emcc-test"\n\
rustflags = "-C link-args=-fPIC -C relocation-model=pic -v"\n\
' > config.toml

RUN echo -n "\
$(echo '#')!/bin/bash\n\
source \"/emsdk/emsdk_env.sh\"\n\
cd /project\n\
mkdir .cargo\n\
cp /config.toml .cargo/\n\
cargo build --release --target=wasm32-unknown-emscripten \n\
" > compile && chmod +x compile

CMD ["/compile"]