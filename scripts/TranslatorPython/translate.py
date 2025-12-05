import json
import re

import click
import os

from ollama import GenerateResponse, Client

# MODEL = "mixtral:8x22b"
# MODEL = "gemma3:12b"
MODEL = "gemma3:27b"
#MODEL = "mistral:latest"
#MODEL = "llama3.2"

# Ai Studio address on VPN
#OLLAMA_URL = "http://10.1.0.2:11434"
# Ai Studio address in office network
OLLAMA_URL = "http://192.168.1.77:11434"
#OLLAMA_URL = "http://localhost:11434"

TRANSLATION_STATUS = "needs_review"

RAW_LOCALIZATION_PROMPT = """
You are a professional translator and you are used to work with mobile application frameworks.
You have to translate some strings from an iOS instant messaging application.
Original strings are in {original_language} and you have to translate them in {target_language}.
Strings will be passed as json objects, extracted from xcstrings files, preserve this json format.
Set output string state to {translation_status}.

You response must follow this pattern:
Here is the translated string:
```json
REPLACE_WITH_TRANSLATION
```

The string to translate is: {string}
"""


language_map: dict[str, str] = {
    "fr": "french",
    "en": "english",
    "es": "spanish",
    "de": "german",
    "it": "italian",
    "zh-Hans": "simplified chinese",
    "pt": "portuguese"
}

@click.command()
@click.option('-f', '--force', is_flag=True, help="Translate all strings")
@click.option('-l', '--language', help="Language to translate to", required=True, type=str)
@click.option('-d', '--debug', is_flag=True, help="Increase log verbosity")
@click.option('-h', '--host', type=str, default=OLLAMA_URL, help="Ollama server url")
@click.option('-m', '--model', type=str, default=MODEL, help="Ollama model to use")
@click.option('-s', '--status', type=str, default=TRANSLATION_STATUS, help="Translation status to set (default is needs_review)")
@click.option('-t', '--target', type=str, help="Translation status to target (default is nil meaning all new strings are targetted")
@click.argument("files", nargs=-1, type=str, required=True)
def main(language: str, host: str, model: str, files: tuple[str], status: str, target: str, force: bool, debug: bool):
    # test parameters
    if language not in language_map:
        print(f"Language {language} is not supported use one of {', '.join(language_map.keys())} instead")
        return
    for file in files:
        if not os.path.exists(file):
            print(f"file not found: {file}")
            return

    # process file recursively
    for file in files:
        recursively_translate_files(file, language, host, model, status, target, force, debug)


def recursively_translate_files(path: str, target_language: str, ollama_url: str, model: str, status: str, target: str, force: bool, debug: bool):
    # it's a file to translate !
    if os.path.isfile(path) and path.endswith(".xcstrings"):
        with open(path, "rt", encoding="utf-8") as f:
            content: dict = json.load(f)

        original_language = content.get("sourceLanguage") if content.get("original_language") else "en"
        print(f"====================================")
        if original_language == target_language:
            print(f"Skipped already translated file: {path}")
        else:
            print(f"{path}: {original_language} => {target_language}")
        print(f"====================================")

        content = translate_file(content, original_language, target_language, ollama_url, model, status, target, force, debug)
        with open(path, "wt", encoding="utf-8") as f:
            json.dump(content, f, indent=2, ensure_ascii=False, sort_keys=True)

    elif os.path.isdir(path):
        if debug:
            print(f"Found sub-directory: {path}")
        for name in os.listdir(path):
            recursively_translate_files(os.path.join(path, name), target_language, ollama_url, model, status, target, force, debug)


def translate_file(content: dict, original_language: str, target_language: str, ollama_url: str, model: str, status: str, target: str, force: bool, debug: bool) -> dict:
    client = Client(host=ollama_url)

    print(f"Strings in file: {len(content.get('strings'))}")

    # extract only localizations that need translation
    localizations_to_translate: list[tuple[str, dict]] = []
    for string_key, string in content["strings"].items():
        localizations: dict = string.get("localizations")
        if not localizations:
            print(f"‼️ invalid format: localizations field not found (key: {string_key})")
            continue
        original_localization: dict = localizations.get(original_language)
        if not original_localization:
            print(f"❕original sentence not found (key: {string_key})")
            continue

        # check if we can skip string: there is an already translated target language
        if not force and localizations.get(target_language) and not check_if_need_translation(localizations.get(target_language), target):
            continue

        localizations_to_translate.append((string_key, original_localization))

    print(f"Strings to translate: {len(localizations_to_translate)}")

    # run translations tasks
    i = 0
    for string_key, original_localization in localizations_to_translate:
        i += 1
        print(f"translation {i} / {len(localizations_to_translate)}: {string_key}")

        # ollama request
        original_sentence: str = json.dumps(original_localization)
        if debug:
            print(f" => {original_language}: {original_sentence}")
        prompt: str = RAW_LOCALIZATION_PROMPT.format(original_language=language_map[original_language],
                                         target_language=language_map[target_language], string=original_sentence, translation_status=status)
        response: GenerateResponse = client.generate(model=model, prompt=prompt)

        # check response pattern
        if not response.response.count("\n```json\n") == 1 or not response.response.count("```") == 2:
            print(f"⚠️ Invalid response pattern: {response.response}")
            continue

        try:
            target_localization: dict = json.loads(response.response.split("```", 2)[1].removeprefix("json").strip())
        except json.decoder.JSONDecodeError:
            print(f"⚠️ Invalid response format: {response.response}")
            continue

        # compare json structure between original and target
        if not compare_dictionary_structure(original_localization, target_localization) or not compare_dictionary_structure(target_localization, original_localization):
            print(f"⚠️ Translation and original localization does not have the same structure")
            print(f" => {original_localization}")
            print(f" => {target_localization}")
            continue

        # check arguments preserved
        if not have_variables_been_preserved(original_localization, target_localization):
            print(f"⚠️ Variable have been lost during process")
            print(f" => {original_localization}")
            print(f" => {target_localization}")
            continue

        if debug:
            print(f" => {target_language}: {target_localization}")

        content.get("strings").get(string_key).get("localizations")[target_language] = target_localization

    return content


# return True if dictionary contains at least one stringUnit that need translation
def check_if_need_translation(dictionary: dict, target: str) -> bool:
    for key, value in dictionary.items():
        if key == "stringUnit":
            if target:
                return value.get("state") in [target]
            else:
                return value.get("state") not in ["needs_review", "translated"]
        elif type(value) is dict:
            if check_if_need_translation(value, target):
                return True


# return False if at least one field in d1 is not in d2, or does not have the same type
def compare_dictionary_structure(d1: dict, d2: dict) -> bool:
    for key in d1.keys():
        if not d2.get(key):
            return False
        if type(d1[key]) is not type(d2[key]):
            return False
        if type(d1[key]) is dict:
            if not compare_dictionary_structure(d1[key], d2[key]):
                return False
    return True


VARIABLE_PATTERN = r'%[0-9]*\$?[@#]'
# return False if we do not find same variable patterns in d1 and d2 stringUnits
def have_variables_been_preserved(d1: dict, d2: dict) -> bool:
    for key in d1.keys():
        if key == "stringUnit":
            value_1: str = d1.get(key).get("value")
            value_2: str = d2.get(key).get("value")
            variables_1: list[str] = re.findall(VARIABLE_PATTERN, value_1)
            variables_2: list[str] = re.findall(VARIABLE_PATTERN, value_2)
            return sorted(variables_1) == sorted(variables_2)
        # recursive check
        if type(d1[key]) is dict:
            if not have_variables_been_preserved(d1[key], d2[key]):
                return False
    return True


if __name__ == "__main__":
    main()
