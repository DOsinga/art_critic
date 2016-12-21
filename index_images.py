#!/usr/bin/env python
import argparse
import os
import numpy as np
from sklearn.neighbors import NearestNeighbors
import tensorflow as tf
from tensorflow.python.platform import gfile
import pickle
import json
from PIL import Image

BOTTLENECK_TENSOR_NAME = 'pool_3/_reshape:0'
JPEG_DATA_TENSOR_NAME = 'DecodeJpeg/contents:0'


def main(model_path, images_path, image_match_model, thumbnail_path):
  print('loading model')
  sess = tf.Session()
  model_filename = os.path.join(model_path, 'classify_image_graph_def.pb')

  with gfile.FastGFile(model_filename, 'rb') as f:
    graph_def = tf.GraphDef()
    graph_def.ParseFromString(f.read())
    bottleneck_tensor, jpeg_data_tensor = (
        tf.import_graph_def(graph_def, name='', return_elements=[
            BOTTLENECK_TENSOR_NAME, JPEG_DATA_TENSOR_NAME]))


  print('parsing images')
  image_infos = []
  image_vectors = []
  for dn in os.listdir(images_path):
    index_fn = os.path.join(images_path, dn, 'index.json')
    if not os.path.isfile(index_fn):
      continue
    index = json.load(open(index_fn))
    for painting in index['Paintings']:
      fn = os.path.split(painting['image'])[-1]
      image_path = os.path.join(images_path, dn, fn)
      if not os.path.isfile(image_path):
        continue
      if thumbnail_path:
        try:
          im = Image.open(image_path)
        except OSError:
          continue
        except IOError:
          continue
        hash_id = '%02x' % (hash(fn) % 255)
        if not os.path.isdir(os.path.join(thumbnail_path, hash_id)):
          os.mkdir(os.path.join(thumbnail_path, hash_id))
        im.thumbnail((240, 240))
        im.save(os.path.join(thumbnail_path, hash_id, fn))
        painting['thumbnail'] = os.path.join(hash_id, fn)
        painting['thumbnail_width'], painting['thumbnail_height'] = im.size
      image_data = gfile.FastGFile(image_path, 'rb').read()
      bottleneck_values = sess.run(bottleneck_tensor, {jpeg_data_tensor: image_data})
      bottleneck_values = np.squeeze(bottleneck_values)
      image_infos.append(painting)
      image_vectors.append(bottleneck_values)
      print(fn)

  print('building nearest neighbors model')
  nbrs = NearestNeighbors(n_neighbors=20, algorithm='ball_tree').fit(image_vectors)
  print('saving model')
  with open(image_match_model, 'wb') as fout:
    pickle.dump(
        (nbrs, image_infos),
      fout
    )


if __name__ == '__main__':
  parser = argparse.ArgumentParser(description='Index images using inception')
  parser.add_argument('--model_path', type=str, default='imagenet',
                      help='Where the unpacked model dump is')
  parser.add_argument('--images_path', type=str, default='wiki_art',
                      help='Where the images are')
  parser.add_argument('--thumbnail_path', type=str, default='thumbnails',
                      help='Where the images are')
  parser.add_argument('--image_match_model', type=str, default='image_match_model.pickle',
                      help='Where to save the resulting model')

  args = parser.parse_args()
  main(args.model_path, args.images_path, args.image_match_model, args.thumbnail_path)





