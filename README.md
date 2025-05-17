chmod +x install_chatgpt_ai.sh

# Run full install
./install_chatgpt_ai.sh all

# Start CLI assistant:
source "$HOME/chatgpt_venv/bin/activate"
python chat_assistant.py

# Start Web API + UI:
source "$HOME/chatgpt_venv/bin/activate"
python chat_webapi.py

# Update script:
./update_chatgpt_ai.sh
