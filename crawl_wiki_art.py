#!/usr/bin/env python
import multiprocessing
import os
import requests
import json
import argparse
from bs4 import BeautifulSoup
from PIL import Image
from io import BytesIO
import time


def crawl_images(control_queue):
  while not control_queue.empty():
    url, painting_path = control_queue.get()
    r = requests.get(url)
    print(url)
    while r.status_code != 200:
      print(r.status_code)
      time.sleep(1)
      r = requests.get(url)

    else:
      image = Image.open(BytesIO(r.content))
      image.save(open(painting_path, 'wb'))


def main(image_cache):
  root = requests.get('http://www.wikiart.org/en/paintings-by-style').content
  soup = BeautifulSoup(root, 'html.parser')
  for link in soup.find_all('a'):
    href = link.get('href', '')
    if href.startswith('/en/paintings-by-style/'):
      style_id = href.rsplit('/', 1)[-1]
      p = style_id.find('?')
      if p > -1:
        style_id = style_id[:p]
      if style_id == 'by-name':
        continue
      print(style_id)
      path = os.path.join(image_cache, style_id)
      if not os.path.isdir(path):
        os.makedirs(path)
      json_path = os.path.join(path, 'index.json')
      if os.path.isfile(json_path):
        paintings = json.load(open(json_path))
      else:
        paintings = None
        page = 1
        while not paintings or len(paintings['Paintings']) < paintings['AllPaintingsCount']:
          time.sleep(0.2)
          url = 'http://www.wikiart.org/en/paintings-by-style/%s?select=all&json=2&page=%d' % (style_id, page)
          r = requests.get(url)
          if r.status_code != 200:
            print(r)
            break
          recs = r.json()
          if paintings is None:
            paintings = recs
            paintings['id'] = style_id
            paintings['name'] = link.contents[0].split(' (')[0]
            del paintings['PageSize']
          else:
            paintings['Paintings'].extend(recs['Paintings'])
          page += 1
        json.dump(paintings, open(json_path, 'w'), indent=2)

      control_queue = multiprocessing.Queue()
      for painting in paintings['Paintings']:
        url = painting['image']
        painting_path = os.path.join(path, url.rsplit('/')[-1])
        if not os.path.isfile(painting_path):
          control_queue.put((url, painting_path))

      if not control_queue.empty():
        cpu_count = multiprocessing.cpu_count()
        cpu_count = 2
        processes = []
        for task_idx in range(cpu_count):
          p = multiprocessing.Process(target=crawl_images, args=(control_queue,))
          p.start()
          processes.append(p)

        while any(p.is_alive() for p in processes):
          time.sleep(0.1)



if __name__ == '__main__':
  parser = argparse.ArgumentParser(description='Collect painters and their schools')
  parser.add_argument('image_cache', type=str,
                      help='Json file that will hold the result')

  args = parser.parse_args()
  main(args.image_cache)




