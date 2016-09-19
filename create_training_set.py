#!/usr/bin/env python
import multiprocessing
import os
import requests
import json
import argparse
import urllib
import psycopg2
import psycopg2.extras
from PIL import Image
from hashlib import md5
from io import BytesIO
import shutil

def main(json_dir, training_set_dir):
  paintings_by_movement = json.load(file(os.path.join(json_dir, 'paintings_by_movement.json')))
  crawled = json.load(file(os.path.join(json_dir, 'crawled.json')))

  if os.path.isdir(training_set_dir):
    shutil.rmtree(training_set_dir)
  os.makedirs(training_set_dir)

  for school, v in sorted(paintings_by_movement.items(), key=lambda t:len(t[1]), reverse=True)[:11]:
    school_path = os.path.join(training_set_dir, school.replace(' ', '_'))
    os.makedirs(school_path)
    for painting in v:
      pic_path = crawled.get(painting)
      if pic_path:
        try:
          shutil.copy(pic_path, os.path.join(school_path, os.path.split(pic_path)[-1]))
        except OSError:
          pass


if __name__ == '__main__':
  parser = argparse.ArgumentParser(description='Collect painters and their schools')
  parser.add_argument('json_out', type=str,
                      help='Directory where the processed')
  parser.add_argument('training_set', type=str,
                      help='Where the training set will end up')

  args = parser.parse_args()
  main(args.json_out, args.training_set)




