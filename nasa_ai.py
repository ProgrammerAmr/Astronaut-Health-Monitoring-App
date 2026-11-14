import os
import chromadb
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.embeddings import OllamaEmbeddings
from langchain_ollama import OllamaEmbeddings, OllamaLLM
from langchain_community.llms import Ollama


# 1. Read files function
def read_file(folder_path=r"C:\Users\LENOVO\Desktop\for final project\nasa data"):
    """Reads the content of markdown files and returns them as a dictionary."""
    all_data = {}
    
    if not os.path.exists(folder_path):
        raise FileNotFoundError(f"The folder {folder_path} does not exist.")
    
    for root, dirs, files in os.walk(folder_path):
        for filename in files:
            if filename.endswith((".md", ".txt", ".csv")):
                track_name = filename.replace(".md", "").replace(".txt", "").replace(".csv", "")
                full_path = os.path.join(root, filename)
                try:
                    with open(full_path, 'r', encoding='utf-8') as file:
                        content = file.read()
                        all_data[track_name] = content
                except Exception as e:
                    print(f"Error reading file {full_path}: {e}")

    return all_data


# # 2. Embedding and ChromaDB storage function
# def embedding_data(roadmaps_database):
#     """Split roadmap content into chunks and store them into ChromaDB."""
#     print("Chunking data and preparing embeddings...")
#     splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)

#     chroma_client = chromadb.PersistentClient(path="./chroma_db_storage")
#     embedding_function = OllamaEmbeddings(model="llama3")
    
#     collection = chroma_client.get_or_create_collection(
#         name="roadmaps_collection"
#     )

#     documents = []
#     ids = []
#     metadatas = []
    
#     counter = 0
#     for track_name, content in roadmaps_database.items():
#         chunks = splitter.split_text(content)
#         for i, chunk in enumerate(chunks):
#             chunk_id = f"{track_name}_chunk_{i}"
#             documents.append(chunk)
#             ids.append(chunk_id)
#             metadatas.append({"track": track_name})
#             counter += 1

#     print(f"Generating embeddings and adding {counter} chunks to ChromaDB...")
    
#     # Define batch size to prevent server overloading (Error 500)
#     batch_size = 100
#     for i in range(0, len(documents), batch_size):
#         batch_docs = documents[i:i + batch_size]
#         batch_ids = ids[i:i + batch_size]
#         batch_metadatas = metadatas[i:i + batch_size]
        
#         print(f"Processing batch {i} to {i + len(batch_docs)}...")
#         batch_embeddings = embedding_function.embed_documents(batch_docs)
#         # Generate embeddings via Ollama and add to collection
#         embeddings = embedding_function.embed_documents(documents)
    
#     collection.upsert(
#         documents=documents,
#         embeddings=embeddings,
#         ids=ids,
#         metadatas=metadatas
#     )

#     print("Data successfully stored in ChromaDB!")
#     return collection, embedding_function

def embedding_data(roadmaps_database):
    print("Chunking data and preparing embeddings...")
    

    chroma_client = chromadb.PersistentClient(path="./chroma_db_storage")
    embedding_function = OllamaEmbeddings(model="nomic-embed-text")
    collection = chroma_client.get_or_create_collection(name="roadmaps_collection")

    if collection.count() > 0:
        print(f"\n--- ChromaDB already has {collection.count()} chunks! Skipping re-embedding. ---")
        return collection, embedding_function
    
    print("Chunking data and preparing embeddings for the first time...")
    splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
    
    
    documents, ids, metadatas = [], [], []
    for track_name, content in roadmaps_database.items():
        for i, chunk in enumerate(splitter.split_text(content)):
            documents.append(chunk)
            ids.append(f"{track_name}_chunk_{i}")
            metadatas.append({"track": track_name})

    print(f"Generating embeddings for {len(documents)} chunks...")
    batch_size = 100
    for i in range(0, len(documents), batch_size):
        batch_docs = documents[i:i + batch_size]
        print(f"Processing batch {i} to {i + len(batch_docs)}...")
        batch_embeddings = embedding_function.embed_documents(batch_docs)
        collection.upsert(
            documents=batch_docs,
            embeddings=batch_embeddings,
            ids=ids[i:i + batch_size],
            metadatas=metadatas[i:i + batch_size],
        )

    print("Data successfully stored in ChromaDB!")
    return collection, embedding_function

# 3. AI Retrieval and Generation Chat function
# 3. AI Retrieval and Generation Chat function
# 3. AI Retrieval and Generation Chat function
def Ai_chat(query, collection, embedding_function, chat_history):
    """
    Searches ChromaDB for relevant medical chunks, explicitly assesses risk level,
    and provides clear triage status and actionable treatment steps.
    """
    print(f"\nAnalyzing patient telemetry / query: '{query}'...")
    
    query_embedding = embedding_function.embed_query(query)
    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=6
    )
    
    retrieved_chunks = results['documents'][0]
    matched_tracks = results['metadatas'][0]
    
    context = "\n---\n".join(retrieved_chunks)
    history_text = "\n".join([f"Astronaut: {q}\nFlight Surgeon AI: {a}" for q, a in chat_history[-3:]])
    
    # برومبيت صارم جداً يفرض تحديد الحالة (خطر أم لا) وعلاج وخطوات واضحة
    prompt = f"""You are an elite AI Flight Surgeon on a deep-space mission. 
Analyze the astronaut's telemetry report or query and provide an explicit medical assessment.

You MUST structure your response strictly using these exact sections:
1. **PATIENT STATUS**: Choose ONLY ONE option: [🟢 GREEN - Stable] OR [🟡 YELLOW - Caution / Monitor] OR [🔴 RED - HIGH RISK / DANGEROUS].
2. **CLINICAL ASSESSMENT**: State clearly whether the condition is dangerous or life-threatening based on the numbers and the NASA Context.
3. **CLEAR TREATMENT & ACTION STEPS**: Provide 3 to 5 concise, numbered, highly specific actionable steps (no fluff).
4. **MISSION CONTROL ESCALATION**: State clearly whether Mission Control must be contacted immediately.

Previous Conversation History:
{history_text}

NASA Context:
{context}

Astronaut Telemetry / Query:
{query}

Medical Evaluation & Treatment Plan:"""

    llm = OllamaLLM(model="llama3", temperature=0.1) # حرارة منخفضة جداً لالتزام صارم بالهيكل
    print("Generating precise assessment via Ollama...")
    response = llm.invoke(prompt)

    return response, matched_tracks
# 4. Main execution entry point
def main():
    # Step 1: Load documents
    print("--- Step 1: Reading Files ---")
    roadmaps_database = read_file()
    print(f"Successfully loaded {len(roadmaps_database)} markdown tracks!!")

    # Step 2: Embedding and Storage
    print("\n--- Step 2: Processing Embeddings and ChromaDB Storage ---")
    collection, embedding_function = embedding_data(roadmaps_database)
    
    # Step 3: Test AI Chat Assistant
    print("\n--- Step 3: RAG Assistant is Ready! (Type 'exit' to quit) ---")
    chat_history = []
    while True:
        user_query = input("\nYour Question: ")
        if user_query.lower() == 'exit':
            print("Goodbye!")
            break
    
        response, matched_tracks = Ai_chat(user_query, collection, embedding_function,chat_history)
        chat_history.append((user_query, response))
        print("\n=================== AI Assistant Response ===================")
        print(response)
        print("\n=================== Matched Tracks Metadata ===================")
        print(matched_tracks)


if __name__ == "__main__":
    main()