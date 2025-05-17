#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Config variables
PYTHON_VERSION=3.12
VENV_DIR="$HOME/chatgpt_venv"
MODEL_DIR="$HOME/.gpt4all_models"
MODEL_NAME="ggml-gpt4all-l13b-snoozy.bin"
MODEL_URL="https://gpt4all.io/models/$MODEL_NAME"
LOG_DIR="$HOME/chatgpt_ai_logs"
CHAT_HISTORY_DIR="$HOME/chatgpt_chat_history"
PLUGIN_DIR="$HOME/chatgpt_plugins"
API_PORT=5000

# Colors & helpers
print_header() {
  echo -e "${GREEN}==== $1 ====${NC}"
}

print_warning() {
  echo -e "${YELLOW}WARNING: $1${NC}"
}

print_error() {
  echo -e "${RED}ERROR: $1${NC}"
}

# 1. Install Python and basics
install_python() {
  print_header "Installing Python $PYTHON_VERSION and dependencies"
  sudo apt update
  sudo apt install -y software-properties-common
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt update
  sudo apt install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python3-pip wget build-essential libssl-dev portaudio19-dev ffmpeg
  python3 --version
}

# 2. Create Python virtualenv and upgrade pip
create_venv() {
  print_header "Creating Python virtual environment at $VENV_DIR"
  if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
  fi
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip setuptools wheel
}

# 3. Install GPT4All python package, Flask, TTS and dependencies
install_python_packages() {
  print_header "Installing Python packages (gpt4all, flask, tts, plugins)"
  pip install --upgrade gpt4all flask flask_cors pyttsx3 SpeechRecognition
}

# 4. Download GPT4All model
download_model() {
  print_header "Downloading GPT4All model $MODEL_NAME"
  mkdir -p "$MODEL_DIR"
  if [ ! -f "$MODEL_DIR/$MODEL_NAME" ]; then
    wget -O "$MODEL_DIR/$MODEL_NAME" "$MODEL_URL"
  else
    echo "Model already present at $MODEL_DIR/$MODEL_NAME"
  fi
}

# 5. Setup directories for logs, chat history, plugins
setup_dirs() {
  print_header "Setting up log, chat history, and plugin directories"
  mkdir -p "$LOG_DIR" "$CHAT_HISTORY_DIR" "$PLUGIN_DIR"
}

# 6. Check for GPU (CUDA) and print info
check_gpu() {
  print_header "Checking for GPU support"
  if command -v nvidia-smi &>/dev/null; then
    echo "NVIDIA GPU detected. If you have CUDA installed, GPT4All may use GPU acceleration."
  else
    print_warning "No NVIDIA GPU detected. Running on CPU only."
  fi
}

# 7. Print SSH/firewall hardening reminders
print_security_reminders() {
  print_header "Security & access notes"
  echo "- If you expose API or web UI externally, set up SSH keys and firewall rules."
  echo "- Use ufw or iptables to limit access."
  echo "- Consider setting up basic auth for the web UI/API."
}

# 8. Create Python chatbot CLI script with history & TTS support
generate_cli_script() {
  print_header "Generating CLI chat assistant script"

  cat > chat_assistant.py << EOF
import os
import sys
import datetime
import threading
import pyttsx3
import speech_recognition as sr
from gpt4all import GPT4All

MODEL_PATH = os.path.expanduser("$MODEL_DIR/$MODEL_NAME")
LOG_DIR = os.path.expanduser("$LOG_DIR")
CHAT_HISTORY_DIR = os.path.expanduser("$CHAT_HISTORY_DIR")

os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(CHAT_HISTORY_DIR, exist_ok=True)

log_file = os.path.join(LOG_DIR, f"chat_log_\{datetime.date.today()}.txt")
history_file = os.path.join(CHAT_HISTORY_DIR, "session_history.txt")

# Initialize GPT4All model
model = GPT4All(model_name=MODEL_PATH)

# Initialize TTS engine
tts_engine = pyttsx3.init()

def tts_speak(text):
    def speak():
        tts_engine.say(text)
        tts_engine.runAndWait()
    threading.Thread(target=speak).start()

def listen_voice():
    r = sr.Recognizer()
    with sr.Microphone() as source:
        print("Listening... (say 'stop listening' to stop voice input)")
        audio = r.listen(source)
    try:
        query = r.recognize_google(audio)
        print(f"You said: {query}")
        return query
    except Exception as e:
        print(f"Voice recognition error: {e}")
        return None

def log_chat(user_text, response_text):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_file, "a") as f:
        f.write(f"[{timestamp}] User: {user_text}\n")
        f.write(f"[{timestamp}] AI: {response_text}\n")

def main():
    print("Welcome to the GPT4All CLI assistant!")
    print("Type 'exit' or 'quit' to leave.")
    print("Type 'voice' to enter voice input mode.")

    # Load previous history if any
    chat_history = []
    if os.path.exists(history_file):
        with open(history_file, "r") as f:
            chat_history = f.readlines()

    while True:
        user_input = input("You: ").strip()
        if user_input.lower() in ["exit", "quit"]:
            print("Goodbye!")
            break
        elif user_input.lower() == "voice":
            voice_text = listen_voice()
            if voice_text:
                user_input = voice_text
            else:
                continue

        # Add history context (can be improved)
        prompt = "".join(chat_history[-20:]) + f"\nUser: {user_input}\nAI:"

        response = model.generate(prompt=prompt, max_tokens=512)
        print(f"AI: {response.strip()}")
        tts_speak(response.strip())

        # Save chat history & logs
        chat_history.append(f"User: {user_input}\n")
        chat_history.append(f"AI: {response.strip()}\n")
        with open(history_file, "w") as f:
            f.writelines(chat_history)
        log_chat(user_input, response.strip())

if __name__ == "__main__":
    main()
EOF
}

# 9. Create Flask web UI & API server script
generate_flask_api() {
  print_header "Generating Flask web UI and API server"

  cat > chat_webapi.py << EOF
import os
import datetime
from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
from gpt4all import GPT4All
import threading
import pyttsx3

MODEL_PATH = os.path.expanduser("$MODEL_DIR/$MODEL_NAME")
LOG_DIR = os.path.expanduser("$LOG_DIR")
CHAT_HISTORY_DIR = os.path.expanduser("$CHAT_HISTORY_DIR")

os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(CHAT_HISTORY_DIR, exist_ok=True)

app = Flask(__name__)
CORS(app)

model = GPT4All(model_name=MODEL_PATH)
tts_engine = pyttsx3.init()

log_file = os.path.join(LOG_DIR, f"api_chat_log_\{datetime.date.today()}.txt")

def log_chat(user_text, response_text):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_file, "a") as f:
        f.write(f"[{timestamp}] User: {user_text}\n")
        f.write(f"[{timestamp}] AI: {response_text}\n")

def tts_speak(text):
    def speak():
        tts_engine.say(text)
        tts_engine.runAndWait()
    threading.Thread(target=speak).start()

@app.route("/")
def home():
    return render_template_string("""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>GPT4All Web Chat</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    #chat { border: 1px solid #ccc; padding: 10px; height: 400px; overflow-y: scroll; }
    #input { width: 80%; }
    button { padding: 8px 12px; }
    .user { color: blue; }
    .ai { color: green; }
  </style>
</head>
<body>
  <h1>GPT4All Web Chat</h1>
  <div id="chat"></div>
  <input id="input" type="text" placeholder="Type your message" />
  <button onclick="sendMessage()">Send</button>
  <button onclick="speak()">Speak (TTS)</button>

  <script>
    const chat = document.getElementById("chat");
    const input = document.getElementById("input");
    let chatHistory = [];

    function appendMessage(sender, text) {
      const div = document.createElement("div");
      div.className = sender;
      div.textContent = sender.toUpperCase() + ": " + text;
      chat.appendChild(div);
      chat.scrollTop = chat.scrollHeight;
    }

    async function sendMessage() {
      const message = input.value.trim();
      if (!message) return;
      appendMessage("user", message);
      input.value = "";
      chatHistory.push({ role: "user", content: message });

      const response = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ prompt: message }),
      });
      const data = await response.json();
      appendMessage("ai", data.response);
      chatHistory.push({ role: "ai", content: data.response });
    }

    async function speak() {
      const lastAI = chatHistory.slice().reverse().find(m => m.role === "ai");
      if (lastAI) {
        await fetch("/api/tts", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ text: lastAI.content }),
        });
      }
    }

    input.addEventListener("keydown", e => {
      if (e.key === "Enter") sendMessage();
    });
  </script>
</body>
</html>
""")

@app.route("/api/chat", methods=["POST"])
def api_chat():
    data = request.json
    prompt = data.get("prompt", "")
    if not prompt:
        return jsonify({"error": "No prompt provided"}), 400

    response = model.generate(prompt=prompt, max_tokens=512)
    log_chat(prompt, response.strip())
    return jsonify({"response": response.strip()})

@app.route("/api/tts", methods=["POST"])
def api_tts():
    data = request.json
    text = data.get("text", "")
    if text:
        threading.Thread(target=tts_speak, args=(text,)).start()
        return jsonify({"status": "speaking"})
    else:
        return jsonify({"error": "No text provided"}), 400

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=$API_PORT)
EOF
}

# 10. Plugin scaffold generator
generate_plugin_scaffold() {
  print_header "Creating plugin architecture scaffold"
  mkdir -p "$PLUGIN_DIR"
  cat > "$PLUGIN_DIR/sample_plugin.py" << EOF
# Sample plugin for chat assistant
def on_message(message):
    # Modify or analyze message here
    print("Plugin received message:", message)
    return message
EOF
}

# 11. Stub VSCode extension setup helper
generate_vscode_stub() {
  print_header "Generating stub for VSCode extension integration (manual setup required)"
  cat > vscode_integration_instructions.txt << EOF
# VSCode AI Assistant Integration Instructions
- Install 'CodeGPT' or 'ChatGPT' VSCode extension from the marketplace
- Configure extension to use local API endpoint: http://localhost:$API_PORT/api/chat
- Optionally, develop a custom extension that connects to this API for inline code help
- Visit https://code.visualstudio.com/api for extension dev docs
EOF
}

# 12. Auto-update script stub
generate_update_script() {
  print_header "Generating auto-update script"
  cat > update_chatgpt_ai.sh << 'EOF'
#!/bin/bash
set -e
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "Activating virtualenv and updating python packages..."
source "$HOME/chatgpt_venv/bin/activate"
pip install --upgrade gpt4all flask flask_cors pyttsx3 SpeechRecognition

echo "Downloading latest model..."
MODEL_DIR="$HOME/.gpt4all_models"
MODEL_NAME="ggml-gpt4all-l13b-snoozy.bin"
MODEL_URL="https://gpt4all.io/models/$MODEL_NAME"
mkdir -p "$MODEL_DIR"
wget -O "$MODEL_DIR/$MODEL_NAME" "$MODEL_URL"

echo "Update completed!"
EOF
  chmod +x update_chatgpt_ai.sh
}

# 13. Main usage
usage() {
  echo "Usage: $0 [core|packages|model|dirs|checkgpu|security|cli|webapi|plugin|vscode|update|all]"
  echo " core      - Install python and build tools"
  echo " packages  - Install python packages (gpt4all, flask, tts)"
  echo " model     - Download GPT4All model"
  echo " dirs      - Setup directories for logs, history, plugins"
  echo " checkgpu  - Check GPU support"
  echo " security  - Print security & firewall reminders"
  echo " cli       - Generate CLI chat assistant script"
  echo " webapi    - Generate Flask web UI + API server script"
  echo " plugin    - Generate plugin scaffold"
  echo " vscode    - Generate VSCode extension integration stub"
  echo " update    - Generate auto-update script"
  echo " all       - Run all steps in sequence"
  exit 1
}

main() {
  local action=${1:-all}

  case $action in
    core)
      install_python
      create_venv
      ;;
    packages)
      source "$VENV_DIR/bin/activate"
      install_python_packages
      ;;
    model)
      download_model
      ;;
    dirs)
      setup_dirs
      ;;
    checkgpu)
      check_gpu
      ;;
    security)
      print_security_reminders
      ;;
    cli)
      source "$VENV_DIR/bin/activate"
      generate_cli_script
      ;;
    webapi)
      source "$VENV_DIR/bin/activate"
      generate_flask_api
      ;;
    plugin)
      generate_plugin_scaffold
      ;;
    vscode)
      generate_vscode_stub
      ;;
    update)
      generate_update_script
      ;;
    all)
      install_python
      create_venv
      source "$VENV_DIR/bin/activate"
      install_python_packages
      download_model
      setup_dirs
      check_gpu
      print_security_reminders
      generate_cli_script
      generate_flask_api
      generate_plugin_scaffold
      generate_vscode_stub
      generate_update_script
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
