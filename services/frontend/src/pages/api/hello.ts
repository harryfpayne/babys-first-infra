// Next.js API route support: https://nextjs.org/docs/api-routes/introduction
import type { NextApiRequest, NextApiResponse } from "next";

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<any>,
) {
  const url = process.env.API_URL
  console.log(url)
  const response = await fetch(`http://${url}`)
    .then(r => r.text())
    .catch(e => console.error(e))
  res.status(200).json({ response: response });
}
