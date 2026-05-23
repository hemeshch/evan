# Linux Desktop Environment for Evan

This directory provides a Docker-based Linux environment for the Evan bash tool, offering isolated command execution with stateful shell sessions.

## 🚀 Key Features

- **Stateful Shell Sessions**: Commands maintain state (working directory, environment variables, aliases) across executions
- **Lazy Container Initialization**: Containers are only created when first needed, not when conversations start
- **Per-Conversation Isolation**: Each conversation gets its own container with persistent storage
- **No Idle Timeout in Debug Mode**: Containers persist as long as needed during development
- **Skills Directory**: Includes 118 skill files for PDF, DOCX, PPTX, and XLSX processing

## 📁 Directory Structure

```
linux-desktop-environment/
├── README.md                    # This file
├── lazy_agent_manager.py        # Main container manager with lazy initialization
├── stateful_shell.py            # Stateful shell implementation
├── docker/                      # Docker-related files
│   ├── Dockerfile              # Main Ubuntu 24.04 image
│   ├── Dockerfile.agent        # Full-featured agent image
│   ├── Dockerfile.agent-simplified  # Simplified agent image
│   ├── docker-compose.yml      # Docker compose configurations
│   └── .dockerignore
├── scripts/                     # Build and utility scripts
│   ├── build-agent-image.sh    # Build the Docker image
│   ├── build-agent.sh          # Alternative build script
│   ├── build.sh                # Generic build script
│   ├── launch-agent.sh         # Launch agent containers
│   └── verify.sh               # Verify environment setup
├── docs/                        # Documentation
│   ├── README.agent.md         # Agent-specific documentation
│   ├── README.lazy.md          # Lazy initialization docs
│   └── HOST_NETWORK_CONFIG.md  # Network configuration guide
├── skills/                      # Skills directory (118 files)
│   └── public/
│       ├── docx/               # Document processing skills
│       ├── pdf/                # PDF manipulation scripts
│       ├── pptx/               # PowerPoint skills
│       └── xlsx/               # Excel processing utilities
├── archive/                     # Archived older implementations
│   ├── agent_manager.py        # Previous agent manager
│   ├── conversation_api.py     # Old conversation API
│   └── example_integration.py  # Example scripts
└── test-workspace/             # Test files and workspace

```

## 🔧 Quick Start

### 1. Build the Docker Image

```bash
cd scripts
./build-agent-image.sh
```

This creates the `claude-agent:latest` image with:
- Ubuntu 24.04 base
- Python 3.12 with data science stack
- Node.js 18.x with document tools
- All skills pre-installed in `/mnt/skills`

### 2. Use via Evan Debug Interface

```bash
evan debug
```

Then navigate to http://localhost:8069

### 3. Direct API Usage

```python
from evan.tools.linux_desktop_environment.lazy_agent_manager import ConversationAgent

# Create agent for a conversation
agent = ConversationAgent(conversation_id="my-session")

# Execute commands - shell state is maintained!
agent.execute_command("cd /tmp")
agent.execute_command("pwd")  # Will show /tmp
agent.execute_command("export MY_VAR='hello'")
agent.execute_command("echo $MY_VAR")  # Will show 'hello'
```

## 🎯 Stateful Shell Behavior

The shell maintains state across commands:

```bash
# Working directory persists
cd /usr/local
pwd  # Shows: /usr/local

# Environment variables persist
export API_KEY="secret123"
echo $API_KEY  # Shows: secret123

# Aliases persist
alias ll='ls -la'
ll  # Executes: ls -la
```

## ⚙️ Configuration

### Container Settings (in bash_tool.py)
- `idle_timeout`: Set to 0 for no timeout (default in debug mode)
- `memory_limit`: Default 2GB
- `cpu_limit`: Default 2.0 CPUs
- `network_mode`: Host network for full access

### Skills Directory
The skills directory contains 118 files for document processing and is automatically mounted at `/mnt/skills` in every container.

## 🐳 Docker Images

### claude-agent:latest (Recommended)
- Full Ubuntu 24.04 environment
- All document processing tools
- Python and Node.js stacks
- Skills pre-installed

### Building Custom Images
Edit `docker/Dockerfile.agent` and rebuild:
```bash
cd docker
docker build -t my-custom-agent -f Dockerfile.agent .
```

## 🔍 Debugging

### View Container Logs
```bash
docker logs claude-agent-<conversation-id>
```

### Access Container Shell
```bash
docker exec -it claude-agent-<conversation-id> bash
```

### Check Container Status
Use the `bash_status` tool in the debug interface or:
```python
agent.get_stats()
```

## 📝 Notes

- Containers are created lazily on first command execution
- Each conversation maintains its own persistent container
- Shell state (pwd, env, aliases) persists across commands
- The `/mnt` directory is writable and persistent
- Skills are read-only at `/mnt/skills`
- No automatic cleanup when `idle_timeout=0`

## 🚨 Troubleshooting

### Container Won't Start
- Check Docker is running: `docker info`
- Check image exists: `docker images | grep claude-agent`
- Rebuild if needed: `./scripts/build-agent-image.sh`

### Commands Not Maintaining State
- Ensure you're using the same conversation_id
- Check that stateful_shell.py is imported correctly
- Verify the shell state with `env` and `pwd` commands

### Skills Not Found
- Verify skills are in the image: `docker run --rm claude-agent:latest ls -la /mnt/skills`
- Rebuild image if skills are missing

## 📚 Related Documentation

- See `docs/README.lazy.md` for lazy initialization details
- See `docs/HOST_NETWORK_CONFIG.md` for network configuration
- See main Evan documentation for overall architecture