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

IMAGE_PATH_EN = 'http://upload.wikimedia.org/wikipedia/en/%s/%s/%s'
IMAGE_PATH_COMMONS = 'http://upload.wikimedia.org/wikipedia/commons/%s/%s/%s'
IMAGE_MARKERS = ['Size of this preview: <a href="', '<div class="fullMedia"><a href="']

def fetch_image(image_name, image_cache):
  if not image_name or image_name.endswith('.tiff'):
    return None
  image_name = image_name.strip('[')
  image_name = image_name.replace(' ', '_')
  if image_name[0].upper() != image_name[0]:
    image_name = image_name.capitalize()
  image_name = urllib.quote(image_name.encode('utf-8'))
  if image_name.startswith('%3C%21--_'):
    image_name = image_name[len('%3C%21--_'):]
  file_path = os.path.join(image_cache, image_name)
  if os.path.isfile(file_path):
    return file_path
  else:
    for prefix in 'http://en.wikipedia.org/wiki/', 'http://commons.wikimedia.org/wiki/', 'http://commons.wikimedia.org/wiki/File:':
      request = requests.get(prefix + image_name)
      if request.status_code == 404:
        continue
      html = request.text
      for marker in IMAGE_MARKERS:
        p = html.find(marker)
        if p == -1:
          continue
        p += len(marker)
        p2 = html.find('"', p)
        url = html[p: p2]
        if url.startswith('//'):
          url = 'http:' + url
        r = requests.get(url)
        if r.status_code != 404:
          try:
            image = Image.open(BytesIO(r.content))
            image.save(file(file_path, 'w'))
          except IOError:
            return None
          return file_path
    print 'no img in html', `image_name`
    return None

def crawl_image(task_id, control_queue, result_queue, image_cache):
  while not control_queue.empty():
    next_image = control_queue.get()
    path = fetch_image(next_image, image_cache=image_cache)
    result_queue.put((path, next_image))


def main(json_dir, image_cache):
  paintings_by_movement = json.load(file(os.path.join(json_dir, 'paintings_by_movement.json')))

  target = 0
  control_queue = multiprocessing.Queue()
  for k, v in sorted(paintings_by_movement.items(), key=lambda t:len(t[1]), reverse=True):
    for painting in v:
      control_queue.put(painting)
      target += 1

  result_queue = multiprocessing.Queue()

  cpu_count = multiprocessing.cpu_count()
  #cpu_count = 1
  processes = []
  for task_idx in range(cpu_count):
    p = multiprocessing.Process(target=crawl_image, args=(task_idx, control_queue, result_queue, image_cache))
    p.start()
    processes.append(p)

  res = {}
  fetched = 0
  missed = 0
  while any(p.is_alive() for p in processes):
    while not result_queue.empty():
      path, img_name = result_queue.get(block=False)
      res[img_name] = path
      if path:
        fetched += 1
      else:
        missed += 1
      if fetched % 25 == 0:
        print fetched, missed, sum(1 for p in processes if p.is_alive())
  json.dump(res, file(os.path.join(json_dir, 'crawled.json'), 'w'))
  print fetched, 'out of', target


if __name__ == '__main__':
  parser = argparse.ArgumentParser(description='Collect painters and their schools')
  parser.add_argument('json_out', type=str,
                      help='Directory where the processed')
  parser.add_argument('image_cache', type=str,
                      help='Json file that will hold the result')

  args = parser.parse_args()
  main(args.json_out, args.image_cache)




