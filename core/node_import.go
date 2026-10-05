package main

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"unicode"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/common/convert"
	"github.com/metacubex/mihomo/common/yaml"
	yamlv3 "go.yaml.in/yaml/v3"
)

// Import only node definitions; subscription rules, groups and providers never
// enter the destination profile. Conversion uses the bundled Mihomo version.
func parseImportedNodes(input string) ([]map[string]any, error) {
	input = strings.TrimSpace(strings.TrimPrefix(input, "\ufeff"))
	if input == "" {
		return nil, fmt.Errorf("请输入节点 / Enter node definitions")
	}
	var raw any
	var nodes []map[string]any
	decoder := yamlv3.NewDecoder(strings.NewReader(input))
	var trailing any
	if decoder.Decode(&raw) == nil && decoder.Decode(&trailing) == io.EOF {
		switch value := raw.(type) {
		case map[string]any:
			if proxies, ok := value["proxies"]; ok {
				list, ok := proxies.([]any)
				if !ok {
					return nil, fmt.Errorf("proxies 必须是列表 / proxies must be a list")
				}
				for _, item := range list {
					node, ok := item.(map[string]any)
					if !ok {
						return nil, fmt.Errorf("节点必须是对象 / A node must be an object")
					}
					nodes = append(nodes, node)
				}
			} else if _, ok := value["type"]; ok {
				nodes = append(nodes, value)
			} else {
				return nil, fmt.Errorf("订阅中没有 proxies 节点 / No proxies in the subscription")
			}
		case []any:
			for _, item := range value {
				node, ok := item.(map[string]any)
				if !ok {
					return nil, fmt.Errorf("节点必须是对象 / A node must be an object")
				}
				nodes = append(nodes, node)
			}
		}
	}
	if nodes == nil {
		// Also accept Base64 subscriptions, mixed links/flow objects, and pasted
		// '- {...}' rows whose indentation differs between nodes.
		text := strings.TrimSpace(string(convert.DecodeBase64([]byte(input))))
		for len(text) > 0 {
			text = strings.TrimLeftFunc(text, unicode.IsSpace)
			if text == "" {
				break
			}
			if text[0] == '#' {
				_, text, _ = strings.Cut(text, "\n")
				continue
			}
			if strings.HasPrefix(text, "- ") {
				text = strings.TrimLeftFunc(text[2:], unicode.IsSpace)
			}
			if strings.HasPrefix(text, "{") {
				end, err := flowNodeEnd(text)
				if err != nil {
					return nil, err
				}
				var node map[string]any
				if yaml.Unmarshal([]byte(text[:end]), &node) != nil || node == nil {
					return nil, fmt.Errorf("第 %d 个节点对象格式错误 / Invalid node object %d", len(nodes)+1, len(nodes)+1)
				}
				nodes = append(nodes, node)
				text = text[end:]
				continue
			}
			line, rest, _ := strings.Cut(text, "\n")
			converted, err := convert.ConvertsV2Ray([]byte(strings.TrimSpace(line)))
			if err != nil || len(converted) != 1 {
				return nil, fmt.Errorf("第 %d 个节点无法识别；请使用 Mihomo YAML/JSON 或有效分享链接 / Unrecognized node %d", len(nodes)+1, len(nodes)+1)
			}
			nodes = append(nodes, converted[0])
			text = rest
		}
	}
	if len(nodes) == 0 {
		return nil, fmt.Errorf("没有可添加的节点 / No nodes to add")
	}
	names := map[string]bool{}
	for i, node := range nodes {
		name, _ := node["name"].(string)
		if strings.TrimSpace(name) == "" {
			name = fmt.Sprintf("%v-%d", node["type"], i+1)
			node["name"] = name
		}
		original := name
		for suffix := 2; names[name]; suffix++ {
			name = fmt.Sprintf("%s (%d)", original, suffix)
		}
		node["name"] = name
		names[name] = true
		proxy, err := adapter.ParseProxy(node)
		if err != nil {
			return nil, fmt.Errorf("第 %d 个节点参数无效 / Invalid parameters for node %d: %w", i+1, i+1, err)
		}
		_ = proxy.Close()
	}
	return nodes, nil
}

// Find the outer closing brace without splitting nested objects or quoted
// credentials. YAML doubled single quotes and JSON escapes are supported.
func flowNodeEnd(text string) (int, error) {
	depth := 0
	var quote byte
	for i := 0; i < len(text); i++ {
		c := text[i]
		if quote != 0 {
			if quote == '"' && c == '\\' {
				i++
			} else if c == quote {
				if quote == '\'' && i+1 < len(text) && text[i+1] == '\'' {
					i++
				} else {
					quote = 0
				}
			}
			continue
		}
		switch c {
		case '"', '\'':
			quote = c
		case '#':
			if i == 0 || unicode.IsSpace(rune(text[i-1])) {
				for i < len(text) && text[i] != '\n' {
					i++
				}
			}
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return i + 1, nil
			}
		}
	}
	return 0, fmt.Errorf("节点大括号或引号未闭合 / Unclosed node braces or quotes")
}

func handleImportNodes(input string) (string, error) {
	nodes, err := parseImportedNodes(input)
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(nodes)
	return string(data), err
}
