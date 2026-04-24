import ray
import socket


@ray.remote
def process_chunk(chunk_id, text):
    host = socket.gethostname()
    return f"[Worker: {host}] chunk {chunk_id}: '{text[:45]}...'"


ray.init()

chunks = [
    (0, "Amazon EKS is a managed Kubernetes service that runs containerized workloads"),
    (1, "Ray is a distributed computing framework for scaling Python applications"),
    (2, "S3 Vectors provides built-in vector storage optimized for similarity search"),
    (3, "Amazon Bedrock gives access to foundation models via a single API"),
    (4, "KubeRay manages Ray cluster lifecycle as Kubernetes custom resources"),
    (5, "RAG combines vector retrieval with LLM generation for grounded answers"),
]

print("Distributing chunks across Ray workers...")
futures = [process_chunk.remote(i, text) for i, text in chunks]
results = ray.get(futures)

print("\nResults:")
for r in results:
    print(r)

print("\nDone. Different hostnames above prove work ran on different pods.")
