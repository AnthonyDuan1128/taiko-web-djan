self.addEventListener('message', async e => {
	const { id, url, type } = e.data
	try{
		const response = await fetch(url)
		if(!response.ok){
			throw new Error(response.status + " " + response.statusText)
		}
		let data
		if(type === "arraybuffer"){
			data = await response.arrayBuffer()
		}else if(type === "blob"){
			data = await response.blob()
		}else{
			data = await response.text()
		}
		self.postMessage({
			id: id,
			data: data
		}, type === "arraybuffer" ? [data] : undefined)
	}catch(e){
		self.postMessage({
			id: id,
			error: e.toString()
		})
	}
})
