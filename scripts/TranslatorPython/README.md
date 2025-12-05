The virtual environment to use in located in the (hidden) .venv folder.
Before calling translate.py, activate the virtual environment.

## How to activate the virtual environment

% source .venv/bin/activate

Check your version of python:

% which python
/Users/XXXXX/Developer/swift-client/scripts/TranslatorPython/.venv/bin/python
% python --version
Python 3.13.7

## Upgrading python and installing packages

Make sure that pip is up-to-date:

% python3 -m pip install --upgrade pip
% python3 -m pip --version
pip 25.2 from /Users/XXXX/Developer/swift-client/scripts/TranslatorPython/.venv/lib/python3.13/site-packages/pip (python 3.13)

To install, e.g., the module named 'click', make sure you activated the virtual environment, then:

% python3 -m pip install click

## Downloading the appropriate Ollama model

Install Ollama, then download the model, e.g., gemma3:27b:

% ollama pull gemma3:27b

Launch the server (localhost):

% ollama serve
Error: listen tcp 127.0.0.1:11434: bind: address already in use

Make sure the port is correct in the translate.py script.

## Translate a file

In Italian:

% python translate.py /Users/tbaigner/Developer/swift-client/Sources/App/ObvAppTypes/Resources/Localizable.xcstrings -l it

To translate all the .xcstrings files of the project:

% python translate.py /Users/tbaigner/Developer/swift-client/Sources/

## How to leave the virtual environment

% deactivate

## Time required to translate an .xcstrings file

On Thomas' Mac Studio, translating 47 strings in one language requires about 2m11 (2.79s per string)
On the offices' AI Mac Studio, translating 47 strings in one language requires about 1m40 (2.12s per string)

## TLDR: How to update the translations

% source .venv/bin/activate
% python translate.py /Users/tbaigner/Developer/swift-client/Sources -l it
% python translate.py /Users/tbaigner/Developer/swift-client/Sources -l es
% deactivate
