#!/bin/sh
gunicorn -b 0.0.0.0:8421 tailer:tailer
