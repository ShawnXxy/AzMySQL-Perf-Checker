using Azure;
using Azure.AI.OpenAI;


public class AskGPT
{
    public static async Task<string> GetResponse(string ask)
    {
        string OPENAI_API_BASE = @"https://orcas-my-perf.openai.azure.com/";
        string OPENAI_API_KEY = @"f34be517035d4c64bcb993256a5b5130";
        string deployments = @"orcas-gpt35-intruct";
        //string role_sys = @"You are a helpful assistant.";

        float temperature = 0.7F;
        int max_tokens = 800;
        float top_n = 0.95F;
        int frequency_penalty = 0;
        int presence_penalty = 0;

        OpenAIClient client = new OpenAIClient(
            new Uri(OPENAI_API_BASE),
            new AzureKeyCredential(OPENAI_API_KEY)
        );

        string prompt = $"Below is an output returned from MySQL system table used to analyze MySQL performance status. Please intepret and summarize the output. Instruction: 1-use the tone as an experienced MySQL DBA; 2-highlight the potential performance impact; 3-gave professional suggestions based on output; 3-if no data output, please respond no data.\n #start of output\n{ask}\n#end of output\n";

        var chatCompletions = new CompletionsOptions()
        {
            Prompts = { prompt },
            Temperature = temperature,
            MaxTokens = max_tokens,
            NucleusSamplingFactor = top_n,
            FrequencyPenalty = frequency_penalty,
            PresencePenalty = presence_penalty
        };


        Response<Completions> responseWithoutStream = await client.GetCompletionsAsync(
            deployments,
            chatCompletions);
        string completions = responseWithoutStream.Value.Choices[0].Text;

        return completions;


    }
}
