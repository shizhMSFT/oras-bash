# oras-bash

`oras.sh` is a subset of [`oras` CLI](https://github.com/oras-project/oras) written in BASH.

To install:

```bash
install_path="$HOME/bin/oras.sh"
curl https://raw.githubusercontent.com/shizhMSFT/oras-bash/main/oras.sh > "$install_path"
chmod +x "$install_path"
```

Try having fun:

```bash
oras.sh repo ls mcr.microsoft.com
```

To access registries with basic auth:

```bash
export ORAS_AUTH="<username>:<password>"
oras.sh $command $sub_command $reference
```
