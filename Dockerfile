FROM elixir:1.18-slim AS builder

ENV MIX_ENV="prod"

RUN apt-get update -y && apt-get install -y build-essential git curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv
COPY assets assets
COPY rel rel

RUN mix assets.deploy && mix compile
RUN mix release

FROM debian:trixie-slim

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

ENV LANG=en_US.UTF-8
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

WORKDIR /app
ENV MIX_ENV="prod"

COPY --from=builder /app/_build/${MIX_ENV}/rel/support_deck ./

ENV PORT=4500
EXPOSE 4500

CMD ["bin/support_deck", "start"]
