# syntax=docker/dockerfile:1.4

# syntax=docker/dockerfile:1.4
FROM --platform=linux/arm64 rust:1.92.0-bookworm AS chef-builder
# ... rest of your original Dockerfile

FROM rust:1.92.0-bookworm AS chef-builder

RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends \
    libclang-dev pkg-config protobuf-compiler nodejs yarn rsync git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-c"]

RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup -i v1.5.1

RUN cargo install cargo-chef --locked

WORKDIR /app

FROM chef-builder AS planner

# Clone fresh from public repo
RUN git clone --depth 1 --branch main https://github.com/alchemyplatform/rundler.git .

# Init only required submodules (public HTTPS)
RUN git submodule update --init --recursive --depth 1 \
    crates/bindings/fastlz/fastlz \
    crates/contracts/contracts/common/lib/forge-std \
    crates/contracts/contracts/v0_6/lib/account-abstraction \
    crates/contracts/contracts/v0_6/lib/openzeppelin-contracts \
    crates/contracts/contracts/v0_7/lib/account-abstraction \
    crates/contracts/contracts/v0_7/lib/openzeppelin-contracts \
    crates/contracts/contracts/v0_8/lib/account-abstraction \
    crates/contracts/contracts/v0_9/lib/account-abstraction

RUN cargo chef prepare --recipe-path recipe.json

FROM chef-builder AS builder

RUN git clone --depth 1 --branch main https://github.com/alchemyplatform/rundler.git .
RUN git submodule update --init --recursive --depth 1 \
    crates/bindings/fastlz/fastlz \
    crates/contracts/contracts/common/lib/forge-std \
    crates/contracts/contracts/v0_6/lib/account-abstraction \
    crates/contracts/contracts/v0_6/lib/openzeppelin-contracts \
    crates/contracts/contracts/v0_7/lib/account-abstraction \
    crates/contracts/contracts/v0_7/lib/openzeppelin-contracts \
    crates/contracts/contracts/v0_8/lib/account-abstraction \
    crates/contracts/contracts/v0_9/lib/account-abstraction

COPY --from=planner /app/recipe.json recipe.json

ARG BUILD_PROFILE=release
ENV BUILD_PROFILE=$BUILD_PROFILE

RUN cargo chef cook --profile $BUILD_PROFILE --recipe-path recipe.json

RUN cargo build --profile $BUILD_PROFILE --locked --bin rundler

FROM ubuntu:24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

COPY --from=builder /app/target/release/rundler /usr/local/bin/rundler

EXPOSE 3000 8080

ENTRYPOINT ["/usr/local/bin/rundler", "node"]
