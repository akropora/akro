# Akro helper models

Akro expects these local helper model names by default:

- `neuron:latest`
- `librarian:latest`
- `coral1.6-prompt:latest`

Pull the published Brain models and create local aliases:

```bash
ollama pull akropora/neuron:latest
ollama pull akropora/librarian:latest
ollama cp akropora/neuron:latest neuron:latest
ollama cp akropora/librarian:latest librarian:latest
```

Build Coral 1.6 Prompt locally:

```bash
ollama create coral1.6-prompt -f models/Modelfile.coral1.6-prompt
```

After publishing it to Ollama, users can instead pull `akropora/coral1.6-prompt:latest` and alias it to `coral1.6-prompt:latest`.
