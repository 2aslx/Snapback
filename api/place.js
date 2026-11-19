import { handleApi } from './_core.js';

export default function handler(req, res) {
  return handleApi(req, res, 'place');
}
