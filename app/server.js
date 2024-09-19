const express = require('express')
const app = express()
const port = 8080

app.get('/', (req, res) => {
  res.send('What a wonderful world!! keep pushing keep learning!')
})

app.listen(port, () => {
  console.log(`Example app listening on port ${port}`)
})
