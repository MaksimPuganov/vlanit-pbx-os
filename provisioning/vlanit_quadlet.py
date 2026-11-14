"""vlanit_quadlet.py — общая работа с quadlet-файлом MikoPBX.

Используются установщиком (installer/lib/deploy.sh) и provisioning
(provisioning/vlanit-provision). Одна реализация — чтобы правки не
расходились (ponytail #25).
"""
import re

ENV_BEGIN, ENV_END = "# VLANIT-ENV-BEGIN", "# VLANIT-ENV-END"


def env_value(v: str) -> str:
    """Значение для Environment= в systemd/quadlet-формате.

    Пробелы/кавычки/обратные слэши — только в кавычках (иначе quadlet
    обрезает значение, подтверждено quadlet -dryrun).
    """
    v = str(v)
    if any(c.isspace() for c in v) or '"' in v:
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return v


def write_env_block(path: str, env_pairs: list) -> None:
    """Записать блок VLANIT-ENV (маркеры) в quadlet, идемпотентно.

    Блок размещается в секции [Container] — Quadlet передаёт Environment=
    в контейнер (--env) только оттуда (дефект 1.2.4).
    """
    content = "\n".join(f"Environment={k}={env_value(v)}" for k, v in env_pairs)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if ENV_BEGIN in text:
        text = re.sub(
            re.escape(ENV_BEGIN) + r".*?" + re.escape(ENV_END),
            ENV_BEGIN + "\n" + content.rstrip() + "\n" + ENV_END,
            text, flags=re.S,
        )
    elif "[Container]" in text:
        text = text.replace(
            "[Container]",
            f"[Container]\n{ENV_BEGIN}\n{content.rstrip()}\n{ENV_END}\n",
            1,
        )
    else:
        raise SystemExit(f"vlanit_quadlet: секция [Container] не найдена в {path}")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
