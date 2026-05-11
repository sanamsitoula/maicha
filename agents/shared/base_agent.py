import json
from agents.shared.ollama_client import chat
from agents.shared.database import query, execute


class BaseAgent:
    def __init__(self, name, system_prompt, model=None):
        self.name = name
        self.model = model
        self.system_prompt = system_prompt
        self.tools = {}
        self.tool_descriptions = []
        self.conversation_history = []

    def register_tool(self, name, description, parameters, function):
        self.tools[name] = function
        self.tool_descriptions.append({
            "name": name,
            "description": description,
            "parameters": parameters,
        })

    def _build_system_prompt(self):
        tools_text = ""
        if self.tool_descriptions:
            tools_text = "\n\nYou have access to the following tools:\n"
            for tool in self.tool_descriptions:
                tools_text += f"\n**{tool['name']}**: {tool['description']}\n"
                tools_text += f"  Parameters: {json.dumps(tool['parameters'])}\n"
            tools_text += "\nWhen you need to use a tool, respond with EXACTLY this format (and nothing else):\n"
            tools_text += 'TOOL_CALL: {"tool": "tool_name", "params": {"param1": "value1"}}\n'
            tools_text += "\nAfter receiving the tool result, formulate your final response to the user.\n"
            tools_text += "If you don't need a tool, just respond normally.\n"
        return self.system_prompt + tools_text

    def _parse_tool_call(self, response):
        if "TOOL_CALL:" in response:
            try:
                json_str = response.split("TOOL_CALL:")[1].strip()
                brace_count = 0
                end_idx = 0
                for i, char in enumerate(json_str):
                    if char == '{':
                        brace_count += 1
                    elif char == '}':
                        brace_count -= 1
                        if brace_count == 0:
                            end_idx = i + 1
                            break
                json_str = json_str[:end_idx]
                tool_call = json.loads(json_str)
                return tool_call.get("tool"), tool_call.get("params", {})
            except (json.JSONDecodeError, IndexError):
                return None, None
        return None, None

    def _execute_tool(self, tool_name, params):
        if tool_name in self.tools:
            try:
                result = self.tools[tool_name](**params)
                return json.dumps(result, default=str)
            except Exception as e:
                return json.dumps({"error": str(e)})
        return json.dumps({"error": f"Unknown tool: {tool_name}"})

    def process_message(self, user_message):
        self.conversation_history.append({"role": "user", "content": user_message})
        messages = [{"role": "system", "content": self._build_system_prompt()}] + self.conversation_history
        response = chat(messages, model=self.model)
        tool_name, params = self._parse_tool_call(response)
        if tool_name:
            tool_result = self._execute_tool(tool_name, params)
            self.conversation_history.append({"role": "assistant", "content": response})
            self.conversation_history.append({"role": "user", "content": f"Tool result for {tool_name}: {tool_result}"})
            messages = [{"role": "system", "content": self._build_system_prompt()}] + self.conversation_history
            final_response = chat(messages, model=self.model)
            self.conversation_history.append({"role": "assistant", "content": final_response})
            return final_response
        else:
            self.conversation_history.append({"role": "assistant", "content": response})
            return response

    def reset_conversation(self):
        self.conversation_history = []
